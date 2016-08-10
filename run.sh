#!/bin/bash
set -e

# Get the kubernetes API bearer token
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# Get the AWS ELB details
REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
ELB_DNS=$(curl -sSk -H "Authorization: Bearer $KUBE_TOKEN" \
  "https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT/api/v1/namespaces/kube-system/services/$SERVICE_NAME" | \
  jq -r '.status.loadBalancer.ingress[0].hostname')
ELB_NAME=$(echo "$ELB_DNS" | awk -F '-' '{ print $2 }')
ELB_HOSTED_ZONE_ID=$(aws --region "$REGION" elb describe-load-balancers --load-balancer-name "$ELB_NAME" | jq -r .LoadBalancerDescriptions[0].CanonicalHostedZoneNameID)

# Generate the FQDN for the requested DNS name
HOSTED_ZONE_DOMAIN=$(aws route53 get-hosted-zone --id "$HOSTED_ZONE_ID" | jq -r .HostedZone.Name)
DNS_NAME=$(echo "$DNS_NAME" | sed "s/.$HOSTED_ZONE_DOMAIN//")
DNS_NAME="${DNS_NAME}.${HOSTED_ZONE_DOMAIN}"

# Create the change batch record to add the DNS entry in the given AWS hosted zone
CHANGE_BATCH="{
  \"Changes\": [
    {
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"$DNS_NAME\",
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
