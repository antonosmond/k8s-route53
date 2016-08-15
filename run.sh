#!/bin/bash
set -e

# Set defaults for optional values
SERVICE_NAMESPACE="${SERVICE_NAMESPACE:-default}"
EVALUATE_TARGET_HEALTH="${EVALUATE_TARGET_HEALTH:-true}"

# Ensure the FQDN ends in a period '.' to make matching with hosted zone values easier
FQDN=$(echo "$FQDN" | sed 's|\.*$|.|')

# Get the hosted zone ID for the requested FQDN
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones | \
  jq -r --arg FQDN "$FQDN" '.HostedZones | map(select(.Name | inside($FQDN))) | max_by(.Name | length) | .Id | ltrimstr("/hostedzone/")')
if [[ -z "$HOSTED_ZONE_ID" || "$HOSTED_ZONE_ID" == 'null' ]]; then
  echo "Failed to get route53 hosted zone ID for $FQDN"
  exit 1
fi

# Get the AWS Region
REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
if [[ -z "$REGION" || "$REGION" == 'null' ]]; then
  echo "Failed to get AWS region from instance metdata: 169.254.169.254/latest/dynamic/instance-identity/document"
  exit 1
fi

# Get the token for the kubernetes API
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
if [[ -z "$KUBE_TOKEN" ]]; then
  echo "Failed to get kubernetes API token from /var/run/secrets/kubernetes.io/serviceaccount/token"
  exit 1
fi

# Get the AWS ELB DNS name from the kubernetes service
ELB_DNS=$(curl -sSk -H "Authorization: Bearer $KUBE_TOKEN" \
  "https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT/api/v1/namespaces/$SERVICE_NAMESPACE/services/$SERVICE_NAME" | \
  jq -r '.status.loadBalancer.ingress[0].hostname')
if [[ -z "$ELB_DNS" || "$ELB_DNS" == 'null' ]]; then
  echo "Failed to get DNS name for kubernetes service $SERVICE_NAME in namespace $SERVICE_NAMESPACE"
  exit 1
fi

# Get the hosted zone ID for the ELB
ELB_HOSTED_ZONE_ID=$(aws --region "$REGION" elb describe-load-balancers | \
  jq -r --arg ELB_DNS "$ELB_DNS" '.LoadBalancerDescriptions | map(select(.DNSName == $ELB_DNS))[0].CanonicalHostedZoneNameID')
if [[ -z "$ELB_HOSTED_ZONE_ID" || "$ELB_HOSTED_ZONE_ID" == 'null' ]]; then
  echo "Failed to get AWS hosted zone ID for ELB: $ELB_DNS"
  exit 1
fi

# Output config values
echo -e "\nCONFIG"
echo "------"
echo "Kubernetes Namespace  : $SERVICE_NAMESPACE"
echo "Kubernetres Service   : $SERVICE_NAME"
echo "AWS Region            : $REGION"
echo "ELB DNS               : $ELB_DNS"
echo "ELB Hosted Zone ID    : $ELB_HOSTED_ZONE_ID"
echo "FQDN                  : $FQDN"
echo "Route53 Hosted Zone ID: $HOSTED_ZONE_ID"
echo "Evaluate Target Health: $EVALUATE_TARGET_HEALTH"

# Create the change batch record to add the DNS entry in the given AWS hosted zone
CHANGE_BATCH="{
  \"Changes\": [
    {
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"$FQDN\",
        \"Type\": \"A\",
        \"AliasTarget\": {
          \"HostedZoneId\": \"$ELB_HOSTED_ZONE_ID\",
          \"DNSName\": \"$ELB_DNS\",
          \"EvaluateTargetHealth\": $EVALUATE_TARGET_HEALTH
        }
      }
    }
  ]
}"

echo -e "\nCHANGE BATCH"
echo "------------"
echo "$CHANGE_BATCH"

# Submit the change batch request
echo -e "\nRESULT"
echo "------"
aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" --change-batch "$CHANGE_BATCH"
