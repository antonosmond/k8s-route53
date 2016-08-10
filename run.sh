#!/bin/bash
set -e

# Get the hosted zone ID for the requested FQDN
DNS_FQDN=$(echo "$DNS_FQDN" | sed 's|\.*$|.|')
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones | \
  jq -r --arg DNS_FQDN "$DNS_FQDN" '.HostedZones | map(select(.Name | inside($DNS_FQDN))) | max_by(.Name | length) | .Id | ltrimstr("/hostedzone/")')

# Get the AWS ELB details
REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
ELB_DNS=$(curl -sSk -H "Authorization: Bearer $KUBE_TOKEN" \
  "https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT/api/v1/namespaces/$SERVICE_NAMESPACE/services/$SERVICE_NAME" | \
  jq -r '.status.loadBalancer.ingress[0].hostname')
ELB_HOSTED_ZONE_ID=$(aws --region "$REGION" elb describe-load-balancers | \
  jq -r --arg ELB_DNS "$ELB_DNS" '.LoadBalancerDescriptions | map(select(.DNSName == $ELB_DNS))[0].CanonicalHostedZoneNameID')

# Default EVALUATE_TARGET_HEALTH if not already set
EVALUATE_TARGET_HEALTH="${EVALUATE_TARGET_HEALTH:-true}"

echo -e "\nCONFIG"
echo "------"
echo "Kubernetes Namespace  : $SERVICE_NAMESPACE"
echo "Kubernetres Service   : $SERVICE_NAME"
echo "AWS Region            : $REGION"
echo "ELB DNS               : $ELB_DNS"
echo "ELB Hosted Zone ID    : $ELB_HOSTED_ZONE_ID"
echo "DNS FQDN              : $DNS_FQDN"
echo "Route53 Hosted Zone ID: $HOSTED_ZONE_ID"
echo "Evaluate Target Health: $EVALUATE_TARGET_HEALTH"

# Create the change batch record to add the DNS entry in the given AWS hosted zone
CHANGE_BATCH="{
  \"Changes\": [
    {
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"$DNS_FQDN\",
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

echo -e "\nRESULT"
echo "------"
# Submit the change batch request
aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" --change-batch "$CHANGE_BATCH"
