# Deploying AWS Network Firewall in a Distributed Architecture with an ALB (v3)

> A step-by-step guide to deploying AWS Network Firewall in a **distributed, multi-AZ** architecture using Terraform — with an Application Load Balancer fronting web servers in private subnets.

---

## Table of Contents

- [Introduction](#introduction)
- [Architecture Overview](#architecture-overview)
- [Traffic Flow](#traffic-flow)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [Testing](#testing)
- [Monitoring & Logging](#monitoring--logging)
- [Cleanup](#cleanup)
- [Key Takeaways](#key-takeaways)

---

## Introduction

Building a resilient network on AWS starts with the fundamental security layers of Amazon VPC. While tools like Security Groups and Network ACLs are indispensable for basic traffic filtering, they are often insufficient for modern compliance standards. To truly secure high-value workloads, teams need more than just port-based rules; they require deep packet inspection (DPI), application protocol detection, and the ability to enforce strict domain-based filtering.

For these advanced requirements, we use **AWS Network Firewall**—a stateful, managed service designed for scale and high-performance security. While basic implementations are straightforward, this post focuses on the **Distributed Deployment Model (v3)**. We will walk through how to integrate an Application Load Balancer (ALB) with firewall endpoints in every Availability Zone to ensure all traffic is inspected while eliminating cross-AZ data transfer costs. 

Using Terraform, we’ll demonstrate how to automate the complex "routing magic" required to place the firewall directly into the traffic path of your private web servers, providing a robust template for defense-in-depth.

---

## Architecture Overview

```
                        ┌─────────────────┐
                        │    Internet      │
                        └────────┬────────┘
                                 │
                        ┌────────▼────────┐
                        │  Internet GW    │
                        │  (Edge RT)      │
                        └───┬─────────┬───┘
                            │         │
              ┌─────────────▼──┐  ┌───▼─────────────┐
              │  Firewall AZ-a │  │  Firewall AZ-b   │
              │  10.0.3.0/28   │  │  10.0.4.0/28     │
              │  (NFW Endpt)   │  │  (NFW Endpt)     │
              └─────────┬──────┘  └─────┬────────────┘
                        │               │
              ┌─────────▼──────┐  ┌─────▼────────────┐
              │  Public AZ-a   │  │  Public AZ-b      │
              │  10.0.1.0/24   │  │  10.0.2.0/24      │
              │  (ALB)         │  │  (ALB)             │
              └─────────┬──────┘  └─────┬────────────┘
                        │               │
              ┌─────────▼──────┐  ┌─────▼────────────┐
              │  Private AZ-a  │  │  Private AZ-b     │
              │  10.0.10.0/24  │  │  10.0.20.0/24     │
              │  Web Server    │  │  Web Server        │
              └────────────────┘  └──────────────────┘
```

### Subnet Layout

| Subnet Tier | AZ-a CIDR | AZ-b CIDR | Purpose |
|---|---|---|---|
| **Public** | `10.0.1.0/24` | `10.0.2.0/24` | ALB |
| **Firewall** | `10.0.3.0/28` | `10.0.4.0/28` | Network Firewall endpoints |
| **Private** | `10.0.10.0/24` | `10.0.20.0/24` | EC2 web servers |

### Key Resources

| Resource | Count | Purpose |
|---|---|---|
| VPC | 1 | `10.0.0.0/16` with DNS support |
| Internet Gateway | 1 | Internet access |
| Regional NAT Gateway | 1 | Outbound internet for private subnets (spans both AZs) |
| Network Firewall | 1 | Distributed across 2 AZs |
| ALB | 1 | Internet-facing load balancer |
| EC2 Instances | 2 | Apache web servers |

---

## Traffic Flow

### Inbound (Internet → Web Servers)

1. Client sends HTTP request to the **ALB's DNS name**.
2. Traffic enters the VPC through the **Internet Gateway**.
3. The **IGW edge route table** directs traffic destined for the public subnets to the **Network Firewall endpoint** in the matching AZ.
4. The NFW endpoint **inspects** the traffic against stateless and stateful rules.
5. Inspected traffic reaches the **ALB** in the public subnet.
6. The ALB forwards the request to a healthy **web server** in the private subnet.

### Outbound (Web Servers → Internet)

1. Web server sends outbound traffic (e.g., `dnf update`).
2. The **private route table** sends `0.0.0.0/0` to the **Regional NAT Gateway**.
3. The **public route table** sends `0.0.0.0/0` to the **NFW endpoint** in the same AZ.
4. The NFW endpoint **inspects** the outbound traffic.
5. The **firewall route table** sends `0.0.0.0/0` to the **Internet Gateway**.
6. Traffic exits through the Regional NAT Gateway's Elastic IP.

---

## Prerequisites

- **Terraform** >= 1.5 installed ([download](https://developer.hashicorp.com/terraform/downloads))
- **AWS CLI** configured with credentials that have sufficient permissions
- An **AWS account** with Network Firewall enabled in the target region

---

## Deployment

### 1. Clone the Repository

```bash
git clone https://github.com/<your-org>/tf-distributed-nfw-alb.git
cd tf-distributed-nfw-alb
```

### 2. Review Variables

Edit `variables.tf` or create a `terraform.tfvars` file to customize:

```hcl
# terraform.tfvars
aws_region         = "us-east-1"
availability_zones = ["us-east-1a", "us-east-1b"]
instance_type      = "t3.micro"
```

### 3. Initialize and Deploy

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Deployment takes approximately **5-10 minutes**. The Network Firewall is the longest-running resource to provision.

### 4. Get the ALB URL

```bash
terraform output alb_url
```

---

## Testing

### Verify Web Servers

Open the ALB URL in your browser. You should see:

```
🔥 AWS Network Firewall — Distributed Architecture
Instance ID: i-0abc123def456
Availability Zone: us-east-1a
Traffic to this page was inspected by AWS Network Firewall.
```

Refresh several times — the ALB will round-robin between the two web servers in different AZs.

### Verify Firewall Inspection

1. Navigate to **VPC → Network Firewall → Firewalls** in the AWS Console.
2. Select the firewall and check the **Monitoring** tab for traffic metrics.
3. Check **CloudWatch Logs** under the log groups:
   - `/aws/network-firewall/nfw-distributed-demo/alert` — rule match alerts
   - `/aws/network-firewall/nfw-distributed-demo/flow` — flow logs

### Test with SSM Session Manager

Since web servers are in private subnets with no public IPs, use SSM:

```bash
INSTANCE_ID=$(terraform output -json web_server_instance_ids | jq -r '.[0]')
aws ssm start-session --target $INSTANCE_ID
```

From the session:

```bash
# Test outbound connectivity (goes through NFW → Regional NAT GW → IGW)
curl -I https://aws.amazon.com
```

---

## Monitoring & Logging

### Network Firewall Logs

| Log Type | CloudWatch Log Group | Content |
|---|---|---|
| **Alert** | `/aws/network-firewall/.../alert` | Stateful rule match events |
| **Flow** | `/aws/network-firewall/.../flow` | All traffic flow records |

### VPC Flow Logs

VPC Flow Logs capture all traffic at the ENI level and are sent to:

```
/aws/vpc-flow-logs/nfw-distributed-demo
```

### Useful CloudWatch Insights Query

```sql
fields @timestamp, event.src_ip, event.dest_ip, event.dest_port, event.proto, event.alert.action
| filter event.alert.action = "allowed"
| sort @timestamp desc
| limit 50
```

---

## Cleanup

```bash
terraform destroy
```

> **Note**: Destruction takes approximately 5-10 minutes as the Network Firewall resources are de-provisioned.

---

## Key Takeaways

1. **Distributed = production-ready**: Deploy firewall endpoints in every AZ where you have workloads to avoid cross-AZ data transfer costs and single points of failure.

2. **Routing is the key**: The entire architecture hinges on route tables directing traffic through NFW endpoints. The IGW edge route table is especially critical for inbound inspection.

3. **Defense in depth**: Combining a private subnet placement, an ALB, security groups, *and* a network firewall provides multiple layers of security.

4. **Stateless → Stateful**: Forward all traffic from the stateless engine to the stateful engine for full 5-tuple + deep packet inspection.

5. **Logging is essential**: Enable both ALERT and FLOW logs from day one. Use CloudWatch Insights for fast troubleshooting.

---

## File Structure

```
.
├── versions.tf      # Terraform & provider versions
├── variables.tf     # Input variables
├── main.tf          # VPC, subnets, IGW, Regional NAT Gateway
├── firewall.tf      # Network Firewall, policy, rule groups
├── routes.tf        # All route tables and routes
├── alb.tf           # Application Load Balancer
├── ec2.tf           # Web servers, IAM, security groups
├── logging.tf       # CloudWatch logs, VPC flow logs
├── outputs.tf       # Output values
└── README.md        # Technical documentation
```

---

## License

This project is licensed under the MIT-0 License.

---

## References

- [AWS Network Firewall Documentation](https://docs.aws.amazon.com/network-firewall/latest/developerguide/)
- [AWS Network Firewall Deployment Models](https://aws.amazon.com/blogs/networking-and-content-delivery/deployment-models-for-aws-network-firewall/)
- [Original CloudFormation Demo](https://github.com/aws-samples/aws-network-firewall-demo)
- [Terraform AWS Provider — Network Firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkfirewall_firewall)
