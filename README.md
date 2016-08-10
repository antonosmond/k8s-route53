# k8s-route53
Creates an Amazon Route53 DNS entry for a Kubernetes service which uses an AWS load balancer.

When using services in kubernetes with AWS load balancers, the load balancer DNS name is unfriendly.
This image is designed to be run as a job in kubernetes and will create an AWS Route53 record for the FQDN you specify, which points to the AWS ELB for the kubernetes service you specify.

IMPORTANT:
This uses the AWS CLI to look up the available hosted zones in Route53 and matches against the FQDN you provide.
If you provide an FQDN and don't have a matching zone in Route53 with that domain then the job will fail.  

### AWS credentials
As the image uses the AWS CLI your kubernetes worker instances must either have an IAM role associated with them or credentials will need to be provided to the container. The following rules are needed:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DescribeLoadBalancers",
        "route53:ListHostedZones",
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
```

### Example kubernetes definition
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: kubernetes-dashboard-dns
spec:
  completions: 1
  template:
    metadata:
      name: kubernetes-dashboard-dns
    spec:
      restartPolicy: Never
      containers:
      - name: kubernetes-dashboard-dns
        image: antonosmond/k8s-route53:latest
        env:
        - name: SERVICE_NAME
          value: kubernetes-dashboard          
        - name: SERVICE_NAMESPACE # optional - defaults to 'default'
          value: kube-system
        - name: FQDN
          value: kubernetes-dashboard.example.com
        - name: EVALUATE_TARGET_HEALTH # optional - defaults to 'true'
          value: "true"
```

The result from the example above would be a Route53 alias record with the FQDN kubernetes-dashboard.example.com which points to the AWS load balancer for the kubernetes service named kubernetes-dashboard.
