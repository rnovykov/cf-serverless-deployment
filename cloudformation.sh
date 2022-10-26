#!/usr/bin/env bash


############################## FUNCTIONS DEFINING ##############################

get_help() {
  cat <<EOF
Usage: ./cloudformation.sh [options]

        Script deploys YourApp infrastructure

        Available options:
         -r             AWS region
                        Default: us-east-1;
         -n             Stack name
                        Default: YourApp;
         -t             Template filename. The file must be in the same folder as script
                        Default: template.yaml;
         -p             Parameters filename. The file must be in the same folder as script
                        Default: parameters.json;
         -i             Build ID which is coming from CI/CD
                        Default: XXX;


Examples:
./cloudformation.sh -r us-east-1 -n YourApp-DEV -t template.yaml -p parameters.json -i "001"
EOF
}

stack_exists() {
    aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}"   \
        --region "${REGION}"           \
        --output "${OUTPUT_FORMAT}"
}

create_stack() {
    aws cloudformation create-stack                                       \
        --stack-name "${STACK_NAME}"                                      \
        --region "${REGION}"                                              \
        --capabilities "CAPABILITY_IAM"                                   \
        --template-body file://"${TEMPLATE_FILENAME}"                     \
        --parameters file://"${PARAMETERS_FOLDER}/${PARAMETERS_FILENAME}" \
        --output "${OUTPUT_FORMAT}"
}

show_stack() {
    aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}"   \
        --region "${REGION}"           \
        --output "${OUTPUT_FORMAT}"
}

create_change_set() {
    aws cloudformation create-change-set                                  \
        --stack-name "${STACK_NAME}"                                      \
        --region "${REGION}"                                              \
        --capabilities "CAPABILITY_IAM"                                   \
        --template-body file://"${TEMPLATE_FILENAME}"                     \
        --change-set-name "${CHANGE_SET_NAME}"                            \
        --description "${DESCRIPTION_PREFIX}=${BUILD_ID}"                 \
        --parameters file://"${PARAMETERS_FOLDER}/${PARAMETERS_FILENAME}" \
        --output "${OUTPUT_FORMAT}"
}

show_change_set() {
    aws cloudformation describe-change-set     \
        --stack-name "${STACK_NAME}"           \
        --region "${REGION}"                   \
        --change-set-name "${CHANGE_SET_NAME}" \
        --output "${OUTPUT_FORMAT}"
}

execute_change_set() {
    aws cloudformation execute-change-set \
        --stack-name "${STACK_NAME}"      \
        --region "${REGION}"              \
        --change-set-name "${CHANGE_SET_NAME}"
}

wait_create() {
    aws cloudformation wait stack-create-complete \
        --stack-name "${STACK_NAME}"              \
        --region "${REGION}"
}

wait_change_set_create() {
    aws cloudformation wait change-set-create-complete \
        --stack-name "${STACK_NAME}"                   \
        --region "${REGION}"                           \
        --change-set-name "${CHANGE_SET_NAME}"
}

wait_update() {
    aws cloudformation wait stack-update-complete \
        --stack-name "${STACK_NAME}"              \
        --region "${REGION}"
}

deploy_rest_api() {
    # Declare and assign separately to avoid masking return values.
    local rest_api_id=""
    local stage_name=""
    
    rest_api_id="$(aws cloudformation describe-stacks                                    \
                        --stack-name "${STACK_NAME}"                                     \
                        --region "${REGION}"                                             \
                        --query "Stacks[0].Outputs[?OutputKey=='RestApiId'].OutputValue" \
                        --output text)"
    
    stage_name="$(aws cloudformation describe-stacks                                     \
                        --stack-name "${STACK_NAME}"                                     \
                        --region "${REGION}"                                             \
                        --query "Stacks[0].Outputs[?OutputKey=='StageName'].OutputValue" \
                        --output text)"
    
    aws apigateway create-deployment                      \
        --region "${REGION}"                              \
        --rest-api-id "${rest_api_id}"                    \
        --stage-name "${stage_name}"                      \
        --description "${DESCRIPTION_PREFIX}=${BUILD_ID}" \
        --output "${OUTPUT_FORMAT}"
}

live_alias_exist() {
  local function_name_output_key="${1}"
  local function_name="" # Declare and assign separately to avoid masking return values.

  function_name="$(aws cloudformation describe-stacks                                                    \
                      --stack-name "${STACK_NAME}"                                                       \
                      --region "${REGION}"                                                               \
                      --query "Stacks[0].Outputs[?OutputKey=='${function_name_output_key}'].OutputValue" \
                      --output text)"

  aws lambda get-alias                 \
    --region "${REGION}"               \
    --function-name "${function_name}" \
    --name "${LIVE_ALIAS_NAME}"        \
    --output table
}

create_live_alias() {
  local function_name_output_key="${1}"
  local function_name="" # Declare and assign separately to avoid masking return values.

  function_name="$(aws cloudformation describe-stacks                                                    \
                      --stack-name "${STACK_NAME}"                                                       \
                      --region "${REGION}"                                                               \
                      --query "Stacks[0].Outputs[?OutputKey=='${function_name_output_key}'].OutputValue" \
                      --output text)"

  aws lambda create-alias              \
    --region "${REGION}"               \
    --function-name "${function_name}" \
    --name "${LIVE_ALIAS_NAME}"        \
    --function-version "\$LATEST"      \
    --output table
}

create_invoke_permissions() {
  local function_name_output_key="${1}"
  local path="${2}"
  local http_method="${3}"
  
  local function_name="" # Declare and assign separately to avoid masking return values.
  function_name="$(aws cloudformation describe-stacks                                                    \
                      --stack-name "${STACK_NAME}"                                                       \
                      --region "${REGION}"                                                               \
                      --query "Stacks[0].Outputs[?OutputKey=='${function_name_output_key}'].OutputValue" \
                      --output text)"

  local account_id="" # Declare and assign separately to avoid masking return values.
  account_id="$(aws cloudformation describe-stacks                                 \
                  --stack-name "${STACK_NAME}"                                     \
                  --region "${REGION}"                                             \
                  --query "Stacks[0].Outputs[?OutputKey=='AccountId'].OutputValue" \
                  --output text)"
  
  local api_gateway_id="" # Declare and assign separately to avoid masking return values.
  api_gateway_id="$(aws cloudformation describe-stacks                             \
                  --stack-name "${STACK_NAME}"                                     \
                  --region "${REGION}"                                             \
                  --query "Stacks[0].Outputs[?OutputKey=='RestApiId'].OutputValue" \
                  --output text)"

  local api_gateway_path=""
  api_gateway_path="$(aws cloudformation describe-stacks                               \
                        --stack-name "${STACK_NAME}"                                   \
                        --region "${REGION}"                                           \
                        --query "Stacks[0].Outputs[?OutputKey=='${path}'].OutputValue" \
                        --output text)"

  # e.g. arn:aws:execute-api:us-east-1:438108700139:2pgbznuio5:/*/GET/app/dictionary/search/*
  local source_arn="arn:aws:execute-api:${REGION}:${account_id}:${api_gateway_id}/*/${http_method}/${api_gateway_path}"

  # Potentially, APIG path that needs to invoke 'live' alias might be changed
  # To bring resource-based policy into desired state, each script execution should re-create static statement
  #
  # Hence, removing policy statement first to avoid ResourceConflictException
  aws lambda remove-permission                            \
    --region "${REGION}"                                  \
    --function-name "${function_name}:${LIVE_ALIAS_NAME}" \
    --statement-id "${STATIC_POLICY_SID}"
  
  # And adding a new one
  aws lambda add-permission                               \
    --region "${REGION}"                                  \
    --function-name "${function_name}:${LIVE_ALIAS_NAME}" \
    --statement-id "${STATIC_POLICY_SID}"                 \
    --action "lambda:InvokeFunction"                      \
    --principal "apigateway.amazonaws.com"                \
    --source-arn "${source_arn}"                          \
    --output "${OUTPUT_FORMAT}"
}

update_config_table() {
    local table_name="" # Declare and assign separately to avoid masking return values.

    
    table_name="$(aws cloudformation describe-stacks                                                  \
                        --stack-name "${STACK_NAME}"                                                  \
                        --region "${REGION}"                                                          \
                        --query "Stacks[0].Outputs[?OutputKey=='ConfigurationTableName'].OutputValue" \
                        --output text)"
    
    for item in "${ITEMS[@]}"; do
        printf '*%.0s' {1..80} # print 80 '*' symbols

        item_relative_path="${ITEMS_FOLDER}/${ENV_NAME}/${item}"

        echo -e "\nPutting  './${item_relative_path}' item to the ${table_name} DynamoDB table ..."
        echo "If PutItem overwrote an attribute name-value pair, then the content of the OLD item is returned. Otherwise, no output ..."
        aws dynamodb put-item                     \
            --region "${REGION}"                  \
            --table-name "${table_name}"          \
            --item file://"${item_relative_path}" \
            --return-values "ALL_OLD"             \
            --output "${OUTPUT_FORMAT}"

    done

}

generate_random_alphabetic_string() {
    head /dev/urandom | tr -cd A-Za-z | head -c "${RANDOM_STR_LENGTH}" ; echo ''
}

print_line() {
    printf '=%.0s' {1..150} # print 150 '=' symbols
}

################################################################################



################################### MAIN BODY ##################################

# Defining constants
RANDOM_STR_LENGTH=64
DESCRIPTION_PREFIX="BuildId"
PARAMETERS_FOLDER='Parameters'
CHANGE_SET_NAME=$(generate_random_alphabetic_string)
STATIC_POLICY_SID="APIG"
ITEMS_FOLDER="DynamoDB"
ITEMS=(
  "GlobalItem.json"
  "Some.json"
)
LIVE_ALIAS_NAME="live"
OUTPUT_FORMAT="yaml"

# *** NOTE: 1-to-1 mapping is ONLY supported ****
# 1) Each Lambda function has its own endpoint in the API Gateway
declare -A LAMBDA_OUTPUTS_DICT
LAMBDA_OUTPUTS_DICT+=(
  ["ConfigurationFunctionName"]="ConfigurationPath"
)

# 2) Each endpoint has SINLGE HTTP method (besides OPTIONS method required for CORS)
declare -A API_ENDPOINTS_DICT
API_ENDPOINTS_DICT+=(
  ["ConfigurationPath"]="GET"

)



# Parsing script options
while getopts r:n:t:p:e:i: option; do
  case "${option}" in
    r) REGION=${OPTARG} ;;
    n) STACK_NAME=${OPTARG} ;;
    t) TEMPLATE_FILENAME=${OPTARG} ;;
    p) PARAMETERS_FILENAME=${OPTARG} ;;
    e) ENV_NAME=${OPTARG} ;;
    i) BUILD_ID=${OPTARG} ;;
    *) get_help && exit 1 ;;
  esac
done

# Initializing default values if they are not specified in options
[[ -z ${REGION} ]] && REGION="us-east-1"
[[ -z ${STACK_NAME} ]] && STACK_NAME="YourApp"
[[ -z ${TEMPLATE_FILENAME} ]] && TEMPLATE_FILENAME="template.yaml"
[[ -z ${PARAMETERS_FILENAME} ]] && PARAMETERS_FILENAME="parameters.json"
[[ -z ${ENV_NAME} ]] && ENV_NAME="ENV_NAME"
[[ -z ${BUILD_ID} ]] && BUILD_ID="0.1.0"

if stack_exists; then
  print_line
  echo -e "\nStack exists, attempting update ..."
  create_change_set

  print_line
  echo -e "\nWaiting for ChangeSet create to complete ..."
  wait_change_set_create

  print_line
  echo -e "\nShow ChangeSet ..."
  show_change_set

  print_line
  echo -e "\nExecute ChangeSet ..."
  if execute_change_set; then
    echo -e "\nWaiting for update ..."
    wait_update

    echo -e "\nForcibly deploying REST API to Stage since CF can't automatically deploy REST API after the changes of Resources ..."
    deploy_rest_api
  else
    echo -e "\nExecute ChangeSet failed ..."
  fi
else
  print_line
  echo -e "\nStack does not exist, creating ..."
  create_stack
  
  print_line
  echo -e "\nWaiting for stack create to complete ..."
  wait_create

  print_line
  echo -e "\nShow stack ..."
  show_stack
fi

for function in "${!LAMBDA_OUTPUTS_DICT[@]}"; do
  if ! live_alias_exist "${function}"; then
    print_line
    echo -e "\nLive alias doesn't exist, creating ..."
    create_live_alias "${function}"
  fi

  print_line
  echo -e "\nRe-creating permissions to invoke live alias ..."
  endpoint="${LAMBDA_OUTPUTS_DICT[${function}]}"
  create_invoke_permissions "${function}" "${endpoint}" "${API_ENDPOINTS_DICT[${endpoint}]}"
done

print_line
echo -e "\nUpdating Configuration DynamoDB table ..."
update_config_table

################################################################################
