# k8s-route53
Creates an Amazon Route53 DNS entry for a Kubernetes service which uses an AWS load balancer.

When using services in kubernetes with AWS load balancers, the load balancer DNS name is unfriendly.
This image is designed to be run as a job in kubernetes and for a given kubernetes service and AWS Route53 hosted zone it will create a DNS record with the name you specify.

### AWS credentials
The image uses the AWS CLI to create the Route53 records. In order for this to work your kubernetes worker instances must either have an IAM role associated with them or credentials will need to be provided to the container. The following rules are needed:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DescribeLoadBalancers",
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
```

### Example kubernetes definitions
```yaml
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: kubernetes-dashboard
  name: kubernetes-dashboard
  namespace: kube-system
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 9090
  selector:
    app: kubernetes-dashboard
---
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
        image: antonosmond/k8s-route53
        env:
        - name: SERVICE_NAME
          value: kubernetes-dashboard          
        - name: SERVICE_NAMESPACE # optional - defaults to 'default'
          value: kube-system
        - name: HOSTED_ZONE_ID
          value: A1B1CD23ABCDEF
        - name: DNS_NAME
          value: kubernetes-dashboard
        - name: EVALUATE_TARGET_HEALTH # optional - defaults to 'true'
          value: true
```

In the example, assuming the hosted zone ID had the domain example.com, the result would be a route53 alias record for kubernetes-dashboard.example.com which points to the AWS load balancer for the kubernetes service named kubernetes-dashboard.
