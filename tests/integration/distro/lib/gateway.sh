# shellcheck shell=bash
# A temporary local S3 gateway (versitygw) serving published repositories over HTTP the way S3
# will: one public-read bucket on a private network the distro containers join. Removed when the
# test file ends, unless gateway.keep is set: then it keeps running, with its files in the run's
# output directory, published on 127.0.0.1:<gateway.port>, for inspection.

[[ -n ${_IT_GATEWAY_SH:-} ]] && return 0
_IT_GATEWAY_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/engine.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/settings.sh"
source "$(dirname "${BASH_SOURCE[0]}")/images.sh"

################################################################################
# The gateway's container and network, named after the run, and the label both carry so kept
# gateways can be found and removed together.
# Outputs:
#   The name or label on stdout.
################################################################################
gateway__name() { echo "distributor-it-gateway-$(settings__get .run.id)"; }
gateway__network() { echo "$(gateway__name)-net"; }
gateway__label() { echo distributor-it=gateway; }

################################################################################
# Whether the gateway is kept after its test file.
# Returns:
#   0 when kept, 1 otherwise.
################################################################################
gateway__kept() { [[ $(settings__get .gateway.keep) == true ]]; }

################################################################################
# The gateway's files: in the run's shared directory (the same path on the host), or the run's
# output directory when kept, since the shared directory is deleted when the run ends.
# Outputs:
#   The path on stdout.
################################################################################
gateway__dir() {
  if gateway__kept; then
    echo "$(settings__get .run.output_dir)/gateway"
  else
    echo "$(settings__get .run.share_dir)/gateway"
  fi
}

################################################################################
# The bucket's base URL, for containers on the gateway's network.
# Outputs:
#   The URL on stdout.
################################################################################
gateway__url() { echo "http://$(gateway__name):7070/repo"; }

################################################################################
# Logs the commands that remove every kept gateway, for the user to run on the host.
################################################################################
gateway__log_removal() {
  log__info "remove every kept gateway with:"
  log__info "  podman rm -f --filter label=$(gateway__label)"
  log__info "  podman network prune -f --filter label=$(gateway__label)"
}

################################################################################
# Starts the gateway with the configured root credentials. Its metadata goes to a sidecar
# directory: its files may be on tmpfs, which may not support the extended attributes versitygw
# uses.
# Globals:
#   IT_ENGINE
# Returns:
#   0, or 1 when it didn't start.
################################################################################
gateway__start() {
  local dir port=()
  dir=$(gateway__dir)
  if gateway__kept; then
    port=(-p "127.0.0.1:$(settings__get .gateway.port):7070")
  fi
  install -d -m 700 "$dir/data" "$dir/meta"
  if ! "$IT_ENGINE" network create --label "$(gateway__label)" "$(gateway__network)" \
    > /dev/null; then
    log__error "can't create the network $(gateway__network)"
    return 1
  fi
  if ! engine__run -d --name "$(gateway__name)" --label "$(gateway__label)" \
    --network "$(gateway__network)" "${port[@]}" -v "$dir:/gw" \
    -e "ROOT_ACCESS_KEY_ID=$(settings__get .gateway.access_key)" \
    -e "ROOT_SECRET_ACCESS_KEY=$(settings__get .gateway.secret_key)" \
    "$(images__versitygw)" posix --sidecar /gw/meta /gw/data > /dev/null; then
    log__error "can't start the gateway"
    if gateway__kept; then
      log__error "is port $(settings__get .gateway.port) held by a kept gateway?"
      gateway__log_removal
    fi
    return 1
  fi
  log__info "gateway: $(gateway__url)"
}

################################################################################
# Uploads a directory's files to the bucket and makes it public-read (objects only: anonymous
# listing stays denied), from a container on the gateway's network.
# Arguments:
#   Directory (a path on the host).
# Returns:
#   0, or 1 when an upload failed.
################################################################################
gateway__load() {
  if ! engine__run -i --network "$(gateway__network)" -v "$1:/src:ro" \
    -e "GATEWAY=http://$(gateway__name):7070" \
    -e "CREDENTIALS=$(settings__get .gateway.access_key):$(settings__get .gateway.secret_key)" \
    "$(images__fedora)" bash -s << 'EOF'; then
set -euo pipefail
auth=(--aws-sigv4 aws:amz:us-east-1:s3 --user "$CREDENTIALS")
# The gateway may still be starting.
for _ in {1..30}; do
  if curl -sf -o /dev/null "${auth[@]}" -X PUT "$GATEWAY/repo"; then break; fi
  sleep 1
done
curl -sSf -o /dev/null "${auth[@]}" -X PUT "$GATEWAY/repo?policy=" --data-binary \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*",
    "Action":["s3:GetObject"],"Resource":["arn:aws:s3:::repo/*"]}]}'
cd /src
find . -type f -printf '%P\n' | while IFS= read -r file; do
  curl -sSf -o /dev/null "${auth[@]}" -T "$file" "$GATEWAY/repo/$file"
done
EOF
    log__error "can't load $1 into the gateway"
    return 1
  fi
  log__info "gateway: loaded $1"
}

################################################################################
# Stops the gateway and deletes its network and files; safe when it never started. A kept
# gateway that's running is left running instead, and how to reach and remove it is logged.
# Globals:
#   IT_ENGINE
################################################################################
gateway__stop() {
  if gateway__kept && "$IT_ENGINE" container exists "$(gateway__name)" 2> /dev/null; then
    log__info "gateway kept: http://127.0.0.1:$(settings__get .gateway.port)/repo" \
      "(access key $(settings__get .gateway.access_key)," \
      "secret key $(settings__get .gateway.secret_key)), files in $(gateway__dir)"
    gateway__log_removal
    return 0
  fi
  "$IT_ENGINE" rm -f "$(gateway__name)" > /dev/null 2>&1
  "$IT_ENGINE" network rm "$(gateway__network)" > /dev/null 2>&1
  rm -rf "$(gateway__dir)"
}
