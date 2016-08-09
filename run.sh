#!/bin/bash
set -e

REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)

SVC=$(kubectl --namespace "${SERVICE_NAMESPACE:-default}" describe svc "$SERVICE_NAME")
HOSTED_ZONE_DOMAIN=$(aws route53 get-hosted-zone --id "$HOSTED_ZONE_ID" | jq -r .HostedZone.Name)
DNS_NAME=$(echo "$DNS_NAME" | sed "s/.$HOSTED_ZONE_DOMAIN//")
DNS_NAME="${DNS_NAME}.${HOSTED_ZONE_DOMAIN}"
ELB_DNS=$(echo "$SVC" | grep 'LoadBalancer Ingress' | awk '{ print $3 }')
ELB_NAME=$(echo "$ELB_DNS" | awk -F '-' '{ print $2 }')
ELB_HOSTED_ZONE_ID=$(aws --region "$REGION" elb describe-load-balancers --load-balancer-name "$ELB_NAME" | jq -r .LoadBalancerDescriptions[0].CanonicalHostedZoneNameID)

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

aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" --change-batch "$CHANGE_BATCH"
