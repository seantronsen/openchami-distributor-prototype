#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Creates the test bucket's AWS resources and records them for the suites and destroy-aws.sh: the
# bucket in ~/.local/state/distributor-it/s3.json (IT_S3_STATE overrides), the access key in
# s3-credentials.json beside it (mode 600; IT_S3_CREDENTIALS overrides):
#
#   bucket distributor-it-<random>    objects public-read, no public listing, every object
#                                     expires after 3 days, standard storage, no versioning
#   IAM user distributor-it-<random>  may only list the bucket and read, write, and delete in
#                                     it; one access key
#
#   init-aws.sh [region]               default: AWS_REGION, else us-east-1
#
# Uses your AWS CLI credentials (an admin; AWS_PROFILE picks a profile). Nothing caps the
# bucket's size; the expiry and the suite's prune keep it small. Refused when either file
# already exists.
set -uo pipefail
# The AWS CLI pages any output on a terminal; nothing here needs it.
export AWS_PAGER=""

# shellcheck source=lib/log.sh
source "$(dirname "$0")/lib/log.sh"
# shellcheck source=lib/random.sh
source "$(dirname "$0")/lib/random.sh"
# shellcheck source=lib/config.sh
source "$(dirname "$0")/lib/config.sh"

################################################################################
# The bucket policy: anyone may read objects (the distros install anonymously); listing isn't
# granted.
# Arguments:
#   Bucket.
# Outputs:
#   The policy (JSON) on stdout.
################################################################################
s3_init__bucket_policy() {
  jq -nc --arg b "$1" '{Version: "2012-10-17", Statement: [{Effect: "Allow", Principal: "*",
    Action: "s3:GetObject", Resource: "arn:aws:s3:::\($b)/*"}]}'
}

################################################################################
# The user's policy: the distributor's needs on this bucket only. s3:ListBucket makes a
# missing object read as missing, not as access denied (docs/operations/deployment.md).
# Arguments:
#   Bucket.
# Outputs:
#   The policy (JSON) on stdout.
################################################################################
s3_init__user_policy() {
  jq -nc --arg b "$1" '{Version: "2012-10-17", Statement: [
    {Effect: "Allow", Action: "s3:ListBucket", Resource: "arn:aws:s3:::\($b)"},
    {Effect: "Allow", Action: ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      Resource: "arn:aws:s3:::\($b)/*"}]}'
}

################################################################################
# Public access: ACLs stay blocked (objects are public only through the bucket policy); the
# public policy is allowed.
# Outputs:
#   The public access block configuration on stdout.
################################################################################
s3_init__public_access() {
  printf '%s' BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,
  printf '%s\n' RestrictPublicBuckets=false
}

################################################################################
# Every object expires after 3 days; unfinished uploads are dropped after 1.
# Outputs:
#   The lifecycle configuration (JSON) on stdout.
################################################################################
s3_init__lifecycle() {
  jq -nc '{Rules: [{ID: "expire", Status: "Enabled", Filter: {}, Expiration: {Days: 3},
    AbortIncompleteMultipartUpload: {DaysAfterInitiation: 1}}]}'
}

################################################################################
# Creates the bucket.
# Arguments:
#   Bucket, region.
# Returns:
#   0, or 1 when a step failed.
################################################################################
s3_init__bucket() {
  local name="$1" region="$2" location=()
  # us-east-1 is the default location and refuses being named.
  if [[ "${region}" != us-east-1 ]]; then
    location=(--create-bucket-configuration "LocationConstraint=${region}")
  fi
  aws s3api create-bucket --bucket "${name}" --region "${region}" "${location[@]}" > /dev/null &&
    aws s3api put-bucket-tagging --bucket "${name}" --region "${region}" \
      --tagging 'TagSet=[{Key=purpose,Value=distributor-it}]' &&
    aws s3api put-public-access-block --bucket "${name}" --region "${region}" \
      --public-access-block-configuration "$(s3_init__public_access)" &&
    aws s3api put-bucket-policy --bucket "${name}" --region "${region}" \
      --policy "$(s3_init__bucket_policy "${name}")" &&
    aws s3api put-bucket-lifecycle-configuration --bucket "${name}" --region "${region}" \
      --lifecycle-configuration "$(s3_init__lifecycle)" > /dev/null
}

################################################################################
# Creates the user and its access key, recorded in the credentials file. The secret goes from
# the AWS CLI to the file through a pipe only.
# Arguments:
#   User (and bucket).
# Returns:
#   0, or 1 when a step failed.
################################################################################
s3_init__user() {
  local name="$1"
  aws iam create-user --user-name "${name}" --tags Key=purpose,Value=distributor-it > /dev/null &&
    aws iam put-user-policy --user-name "${name}" --policy-name bucket \
      --policy-document "$(s3_init__user_policy "${name}")" &&
    (umask 077 && aws iam create-access-key --user-name "${name}" --output json |
      jq '.AccessKey // error("no access key")
        | {access_key_id: .AccessKeyId, secret_access_key: .SecretAccessKey}' \
        > "$(config__file_state_s3_credentials)")
}

main() {
  local region="${1:-${AWS_REGION:-us-east-1}}" file name
  file="$(config__file_state_s3_bucket)"
  if [[ -e "${file}" || -e "$(config__file_state_s3_credentials)" ]]; then
    log__fatal "already initialized: ${file} or $(config__file_state_s3_credentials) exists;" \
      "destroy-aws.sh deletes what they list"
  fi
  if ! aws sts get-caller-identity > /dev/null 2>&1; then
    log__fatal "the AWS CLI has no working credentials (aws configure, or set AWS_PROFILE)"
  fi
  name="distributor-it-$(random__hex 8)"

  # Recorded first, so a failure part way still leaves destroy-aws.sh the names.
  mkdir -p "$(dirname "${file}")" || log__fatal "can't create $(dirname "${file}")"
  if ! jq -n --arg n "${name}" --arg r "${region}" '{bucket: $n, region: $r,
    url: "https://\($n).s3.\($r).amazonaws.com"}' > "${file}"; then
    log__fatal "can't write ${file}"
  fi
  s3_init__bucket "${name}" "${region}" ||
    log__fatal "the bucket ${name} wasn't set up; destroy-aws.sh deletes what was created"
  log__info "created the bucket ${name} (${region})"
  s3_init__user "${name}" ||
    log__fatal "the user ${name} wasn't set up; destroy-aws.sh deletes what was created"
  log__info "created the IAM user ${name} and its access key"
  log__info "recorded in ${file} and $(config__file_state_s3_credentials); the suites use them" \
    "(new access keys can take a minute to work)"
}

main "$@"
