#!/bin/bash
set -e

# Get the hosted zone ID for the requested FQDN
FQDN=$(echo "$FQDN" | sed 's|\.*$|.|')
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones | \
  jq -r --arg FQDN "$FQDN" '.HostedZones | map(select(.Name | inside($FQDN))) | max_by(.Name | length) | .Id | ltrimstr("/hostedzone/")')

# Get the AWS ELB details
REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
ELB_DNS=$(curl -sSk -H "Authorization: Bearer $KUBE_TOKEN" \
  "https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT/api/v1/namespaces/kube-system/services/$SERVICE_NAME" | \
  jq -r '.status.loadBalancer.ingress[0].hostname')
ELB_NAME=$(echo "$ELB_DNS" | awk -F '-' '{ print $2 }')
ELB_HOSTED_ZONE_ID=$(aws --region "$REGION" elb describe-load-balancers --load-balancer-name "$ELB_NAME" | jq -r .LoadBalancerDescriptions[0].CanonicalHostedZoneNameID)

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
          \"EvaluateTargetHealth\": ${EVALUATE_TARGET_HEALTH:-true}
        }
      }
    }
  ]
}"

# Submit the change batch request
aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" --change-batch "$CHANGE_BATCH"
