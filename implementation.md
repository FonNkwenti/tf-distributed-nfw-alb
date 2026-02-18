# Implementation Documentation: AWS Network Firewall Distributed Architecture

This document provides a comprehensive implementation guide for the Terraform-based AWS Network Firewall (NFW) distributed architecture with Application Load Balancer.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [VPC Network Layout](#vpc-network-layout)
3. [Subnet Configuration](#subnet-configuration)
4. [Route Tables](#route-tables)
5. [Network Firewall Configuration](#network-firewall-configuration)
6. [Traffic Flow Analysis](#traffic-flow-analysis)
7. [Security Groups](#security-groups)
8. [Logging and Monitoring](#logging-and-monitoring)
9. [Terraform Resources Reference](#terraform-resources-reference)
10. [Testing Commands](#testing-commands)

---

## Architecture Overview

This implementation deploys a **distributed AWS Network Firewall architecture** within a single VPC, providing centralized traffic inspection for all ingress and egress flows. The architecture uses a sandwich topology where the Network Firewall sits between public-facing resources (ALB) and the internet, as well as between private resources and NAT gateways.

### Key Components

- **VPC**: 10.0.0.0/16 with DNS support enabled
- **3-Tier Subnet Design**:
  - Public subnets (10.0.1.0/24, 10.0.2.0/24) - ALB and NAT Gateways
  - Firewall subnets (10.0.3.0/28, 10.0.4.0/28) - NFW VPC Endpoints
  - Private subnets (10.0.10.0/24, 10.0.20.0/24) - Web servers
- **Multi-AZ Deployment**: Resources distributed across us-east-1a and us-east-1b
- **Network Firewall**: Stateful inspection with Suricata-compatible rules
- **Application Load Balancer**: Internet-facing HTTP load balancer
- **Auto-scaled Web Servers**: EC2 instances serving web content via Apache

### High-Level Architecture Diagram

```
                              INTERNET
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │    Internet Gateway    │
                    │    (igw-xxxxxxxx)      │
                    └───────────┬────────────┘
                                │
              ┌─────────────────┴─────────────────┐
              │         IGW Edge Route Table       │
              │   Routes return traffic per AZ     │
              └─────────────────┬─────────────────┘
              ┌─────────────────┼─────────────────┐
              │                 │                 │
        ┌─────▼─────┐     ┌─────▼─────┐     ┌─────▼─────┐
        │  NFW EP   │     │  NFW EP   │     │  NFW EP   │
        │ AZ1: 3/28 │     │ AZ2: 4/28 │     │ (firewall │
        │ vpc-ep-1  │     │ vpc-ep-2  │     │  subnets) │
        └─────┬─────┘     └─────┬─────┘     └───────────┘
              │                 │
              └────────┬────────┘
                       │
              ┌────────▼────────┐
              │  AWS Network    │
              │    Firewall     │
              │ (Stateful +     │
              │  Stateless)     │
              └────────┬────────┘
                       │
       ┌───────────────┼───────────────┐
       │               │               │
  ┌────▼─────┐   ┌────▼─────┐   ┌─────▼─────┐
  │  ALB     │   │  ALB     │   │  NAT GW   │
  │  AZ1     │   │  AZ2     │   │  per AZ   │
  │ 1.0/24   │   │ 2.0/24   │   │           │
  │ public-1 │   │ public-2 │   │           │
  └────┬─────┘   └────┬─────┘   └─────┬─────┘
       │               │               │
       └───────┬───────┘               │
               │                       │
         ┌─────▼─────┐           ┌─────▼─────┐
         │  Target   │           │  Private  │
         │  Group    │           │  Subnets  │
         └─────┬─────┘           └─────┬─────┘
               │                       │
         ┌─────▼─────┐           ┌─────▼─────┐
         │ Web Svr   │           │ Web Svr   │
         │  AZ1      │           │  AZ2      │
         │ 10.0/24   │           │ 20.0/24   │
         │ private-1 │           │ private-2 │
         └───────────┘           └───────────┘
```

---

## VPC Network Layout

### VPC Configuration

```
┌─────────────────────────────────────────────────────────────────┐
│                    VPC: nfw-distributed-demo-vpc                 │
│                        CIDR: 10.0.0.0/16                        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Availability Zone 1a                  │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │   │
│  │  │ Public       │  │ Firewall     │  │ Private      │   │   │
│  │  │ 10.0.1.0/24  │  │ 10.0.3.0/28  │  │ 10.0.10.0/24 │   │   │
│  │  │ ALB + NAT GW │  │ NFW Endpoint │  │ Web Server   │   │   │
│  │  │ RT: public-1 │  │ RT: fw-1     │  │ RT: private-1│   │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Availability Zone 1b                  │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │   │
│  │  │ Public       │  │ Firewall     │  │ Private      │   │   │
│  │  │ 10.0.2.0/24  │  │ 10.0.4.0/28  │  │ 10.0.20.0/24 │   │   │
│  │  │ ALB + NAT GW │  │ NFW Endpoint │  │ Web Server   │   │   │
│  │  │ RT: public-2 │  │ RT: fw-2     │  │ RT: private-2│   │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Internet Gateway: nfw-distributed-demo-igw                     │
│  IGW Edge RT: Routes return traffic to NFW endpoints per AZ     │
└─────────────────────────────────────────────────────────────────┘
```

### CIDR Allocation Summary

| Subnet Type | AZ1 CIDR | AZ2 CIDR | Purpose |
|-------------|----------|----------|---------|
| Public | 10.0.1.0/24 | 10.0.2.0/24 | ALB, NAT Gateways |
| Firewall | 10.0.3.0/28 | 10.0.4.0/28 | NFW VPC Endpoints |
| Private | 10.0.10.0/24 | 10.0.20.0/24 | Web servers |

---

## Subnet Configuration

### Public Subnets (ALB + NAT Gateways)

```
┌──────────────────────────────────────────────────────────────┐
│ PUBLIC SUBNET - AZ1: us-east-1a                               │
│ CIDR: 10.0.1.0/24                                            │
│ Route Table: nfw-distributed-demo-public-rt-us-east-1a       │
│                                                               │
│ Resources:                                                    │
│ • Application Load Balancer (nfw-distributed-demo-alb)       │
│ • NAT Gateway AZ1                                            │
│ • Elastic IP for NAT Gateway                                 │
│                                                               │
│ Routes:                                                       │
│ ┌─────────────────┬────────────────────────────────────────┐ │
│ │ Destination     │ Target                                 │ │
│ ├─────────────────┼────────────────────────────────────────┤ │
│ │ 10.0.0.0/16     │ local                                  │ │
│ │ 0.0.0.0/0       │ vpc-endpoint (NFW EP AZ1)              │ │
│ └─────────────────┴────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ PUBLIC SUBNET - AZ2: us-east-1b                               │
│ CIDR: 10.0.2.0/24                                            │
│ Route Table: nfw-distributed-demo-public-rt-us-east-1b       │
│                                                               │
│ Resources:                                                    │
│ • Application Load Balancer (multi-AZ)                       │
│ • NAT Gateway AZ2                                            │
│ • Elastic IP for NAT Gateway                                 │
│                                                               │
│ Routes:                                                       │
│ ┌─────────────────┬────────────────────────────────────────┐ │
│ │ Destination     │ Target                                 │ │
│ ├─────────────────┼────────────────────────────────────────┤ │
│ │ 10.0.0.0/16     │ local                                  │ │
│ │ 0.0.0.0/0       │ vpc-endpoint (NFW EP AZ2)              │ │
│ └─────────────────┴────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

### Firewall Subnets (NFW Endpoints)

```
┌──────────────────────────────────────────────────────────────┐
│ FIREWALL SUBNET - AZ1: us-east-1a                             │
│ CIDR: 10.0.3.0/28 (16 IPs)                                   │
│ Route Table: nfw-distributed-demo-firewall-rt-us-east-1a     │
│                                                               │
│ Resources:                                                    │
│ • Network Firewall VPC Endpoint AZ1                          │
│                                                               │
│ Routes:                                                       │
│ ┌─────────────────┬────────────────────────────────────────┐ │
│ │ Destination     │ Target                                 │ │
│ ├─────────────────┼────────────────────────────────────────┤ │
│ │ 10.0.0.0/16     │ local                                  │ │
│ │ 0.0.0.0/0       │ igw (Internet Gateway)                 │ │
│ └─────────────────┴────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ FIREWALL SUBNET - AZ2: us-east-1b                             │
│ CIDR: 10.0.4.0/28 (16 IPs)                                   │
│ Route Table: nfw-distributed-demo-firewall-rt-us-east-1b     │
│                                                               │
│ Resources:                                                    │
│ • Network Firewall VPC Endpoint AZ2                          │
│                                                               │
│ Routes:                                                       │
│ ┌─────────────────┬────────────────────────────────────────┐ │
│ │ Destination     │ Target                                 │ │
│ ├─────────────────┼────────────────────────────────────────┤ │
│ │ 10.0.0.0/16     │ local                                  │ │
│ │ 0.0.0.0/0       │ igw (Internet Gateway)                 │ │
│ └─────────────────┴────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

### Private Subnets (Web Servers)

```
┌──────────────────────────────────────────────────────────────┐
│ PRIVATE SUBNET - AZ1: us-east-1a                              │
│ CIDR: 10.0.10.0/24                                           │
│ Route Table: nfw-distributed-demo-private-rt-us-east-1a      │
│                                                               │
│ Resources:                                                    │
│ • EC2 Web Server (nfw-distributed-demo-web-us-east-1a)       │
│ • Security Group: nfw-distributed-demo-web-sg                │
│ • IAM Instance Profile for SSM                               │
│                                                               │
│ Routes:                                                       │
│ ┌─────────────────┬────────────────────────────────────────┐ │
│ │ Destination     │ Target                                 │ │
│ ├─────────────────┼────────────────────────────────────────┤ │
│ │ 10.0.0.0/16     │ local                                  │ │
│ │ 0.0.0.0/0       │ nat-gateway (AZ1 NAT GW)               │ │
│ └─────────────────┴────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ PRIVATE SUBNET - AZ2: us-east-1b                              │
│ CIDR: 10.0.20.0/24                                           │
│ Route Table: nfw-distributed-demo-private-rt-us-east-1b      │
│                                                               │
│ Resources:                                                    │
│ • EC2 Web Server (nfw-distributed-demo-web-us-east-1b)       │
│ • Security Group: nfw-distributed-demo-web-sg                │
│                                                               │
│ Routes:                                                       │
│ ┌─────────────────┬────────────────────────────────────────┐ │
│ │ Destination     │ Target                                 │ │
│ ├─────────────────┼────────────────────────────────────────┤ │
│ │ 10.0.0.0/16     │ local                                  │ │
│ │ 0.0.0.0/0       │ nat-gateway (AZ2 NAT GW)               │ │
│ └─────────────────┴────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

---

## Route Tables

### IGW Edge Route Table

```
┌──────────────────────────────────────────────────────────────────────────┐
│ IGW EDGE ROUTE TABLE: nfw-distributed-demo-igw-edge-rt                   │
│ Associated with: Internet Gateway                                        │
│ Purpose: Directs return traffic from internet to correct NFW endpoint    │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Routes:                                                                  │
│ ┌──────────────────┬───────────────────────────┬──────────────────────┐ │
│ │ Destination      │ Target                    │ Description          │ │
│ ├──────────────────┼───────────────────────────┼──────────────────────┤ │
│ │ 10.0.1.0/24      │ vpc-endpoint (NFW EP AZ1) │ Return to AZ1 ALB    │ │
│ │ 10.0.2.0/24      │ vpc-endpoint (NFW EP AZ2) │ Return to AZ2 ALB    │ │
│ └──────────────────┴───────────────────────────┴──────────────────────┘ │
│                                                                          │
│ Note: Routes traffic destined for public subnets through the             │
│       corresponding NFW endpoint in each AZ                              │
└──────────────────────────────────────────────────────────────────────────┘
```

### Public Route Tables

```
┌──────────────────────────────────────────────────────────────────────────┐
│ PUBLIC ROUTE TABLE (per AZ): nfw-distributed-demo-public-rt-{az}         │
│ Associated with: Public subnets in each AZ                               │
│ Purpose: Route outbound traffic through Network Firewall                 │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Routes:                                                                  │
│ ┌──────────────────┬───────────────────────────┬──────────────────────┐ │
│ │ Destination      │ Target                    │ Description          │ │
│ ├──────────────────┼───────────────────────────┼──────────────────────┤ │
│ │ 10.0.0.0/16      │ local                     │ VPC internal         │ │
│ │ 0.0.0.0/0        │ vpc-endpoint (NFW EP)     │ Through NFW to IGW   │ │
│ └──────────────────┴───────────────────────────┴──────────────────────┘ │
│                                                                          │
│ AZ-Specific Routing:                                                     │
│ • AZ1 public subnet → NFW endpoint AZ1                                   │
│ • AZ2 public subnet → NFW endpoint AZ2                                   │
└──────────────────────────────────────────────────────────────────────────┘
```

### Firewall Route Tables

```
┌──────────────────────────────────────────────────────────────────────────┐
│ FIREWALL ROUTE TABLE (per AZ): nfw-distributed-demo-firewall-rt-{az}     │
│ Associated with: Firewall subnets in each AZ                             │
│ Purpose: Route inspected traffic to Internet Gateway                     │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Routes:                                                                  │
│ ┌──────────────────┬───────────────────────────┬──────────────────────┐ │
│ │ Destination      │ Target                    │ Description          │ │
│ ├──────────────────┼───────────────────────────┼──────────────────────┤ │
│ │ 10.0.0.0/16      │ local                     │ VPC internal         │ │
│ │ 0.0.0.0/0        │ igw                       │ To Internet          │ │
│ └──────────────────┴───────────────────────────┴──────────────────────┘ │
│                                                                          │
│ Traffic Flow: NFW endpoint → IGW → Internet                              │
└──────────────────────────────────────────────────────────────────────────┘
```

### Private Route Tables

```
┌──────────────────────────────────────────────────────────────────────────┐
│ PRIVATE ROUTE TABLE (per AZ): nfw-distributed-demo-private-rt-{az}       │
│ Associated with: Private subnets in each AZ                              │
│ Purpose: Route outbound traffic through NAT Gateway                      │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Routes:                                                                  │
│ ┌──────────────────┬───────────────────────────┬──────────────────────┐ │
│ │ Destination      │ Target                    │ Description          │ │
│ ├──────────────────┼───────────────────────────┼──────────────────────┤ │
│ │ 10.0.0.0/16      │ local                     │ VPC internal         │ │
│ │ 0.0.0.0/0        │ nat-{az}                  │ To NAT Gateway       │ │
│ └──────────────────┴───────────────────────────┴──────────────────────┘ │
│                                                                          │
│ Traffic Flow: Web Server → NAT GW → NFW → IGW → Internet                │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Network Firewall Configuration

### Firewall Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│ AWS NETWORK FIREWALL: nfw-distributed-demo-nfw                           │
│ VPC: nfw-distributed-demo-vpc                                            │
│ Policy: nfw-distributed-demo-policy                                      │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Subnet Mappings (VPC Endpoints):                                         │
│ ┌─────────────────────────┬─────────────────────────────────────────────┐│
│ │ Availability Zone       │ VPC Endpoint ID                             ││
│ ├─────────────────────────┼─────────────────────────────────────────────┤│
│ │ us-east-1a              │ vpce-xxxxxxxx (10.0.3.0/28)                ││
│ │ us-east-1b              │ vpce-yyyyyyyy (10.0.4.0/28)                ││
│ └─────────────────────────┴─────────────────────────────────────────────┘│
│                                                                          │
│ Policy Components:                                                       │
│ ┌─────────────────────────┬─────────────────────────────────────────────┐│
│ │ Component               │ Configuration                               ││
│ ├─────────────────────────┼─────────────────────────────────────────────┤│
│ │ Stateless Default       │ forward_to_sfe                              ││
│ │ Stateless Fragment      │ forward_to_sfe                              ││
│ │ Stateless Rule Group    │ nfw-distributed-demo-stateless-rg (prio:100)││
│ │ Stateful Rule Group     │ nfw-distributed-demo-stateful-rg            ││
│ └─────────────────────────┴─────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────┘
```

### Stateless Rule Group

```
┌──────────────────────────────────────────────────────────────────────────┐
│ STATELESS RULE GROUP: nfw-distributed-demo-stateless-rg                  │
│ Capacity: 50                                                             │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Rule 1: Forward All to Stateful Engine                                   │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Priority: 10                                                          ││
│ │ Match:                                                                ││
│ │   Source: 0.0.0.0/0                                                   ││
│ │   Destination: 0.0.0.0/0                                              ││
│ │ Action: aws:forward_to_sfe                                            ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│ Purpose: Pass all traffic to stateful inspection engine                  │
└──────────────────────────────────────────────────────────────────────────┘
```

### Stateful Rule Group

```
┌──────────────────────────────────────────────────────────────────────────┐
│ STATEFUL RULE GROUP: nfw-distributed-demo-stateful-rg                    │
│ Capacity: 100                                                            │
│ Type: Suricata-compatible rules                                          │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Allowed Traffic Rules:                                                   │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Rule  │ Protocol │ Flow                   │ Action │ ID        │    ││
│ ├───────┼──────────┼────────────────────────┼────────┼───────────┼────┤│
│ │ HTTP  │ TCP      │ any any → any 80       │ PASS   │ 100001    │    ││
│ │ HTTPS │ TCP      │ any any → any 443      │ PASS   │ 100002    │    ││
│ │ ICMP  │ ICMP     │ any any → any any      │ PASS   │ 100003    │    ││
│ │ HTTP  │ TCP      │ any 80 → any any       │ PASS   │ 100004    │    ││
│ │ HTTPS │ TCP      │ any 443 → any any      │ PASS   │ 100005    │    ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│ Implicit: DROP all traffic not matching PASS rules                       │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Traffic Flow Analysis

### Ingress Traffic Flow: Internet → ALB → Web Server

```
┌──────────────────────────────────────────────────────────────────────────┐
│ INGRESS PATH: HTTP Request from Internet to Web Server                   │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Hop 1: Internet Client                                                   │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Send HTTP request to ALB DNS                                 ││
│ │ Packet: SRC=<client-ip>:<random-port> DST=<alb-public-ip>:80         ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 2: Internet Gateway                                                │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Receive inbound traffic                                      ││
│ │ Routing: IGW has no route table by default, consults subnet RT       ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 3: IGW Edge Route Table                                            │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Route traffic to appropriate NFW endpoint                    ││
│ │ Match: Destination 10.0.1.0/24 (ALB subnet)                          ││
│ │ Route: Forward to NFW VPC Endpoint AZ1                               ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 4: Network Firewall Endpoint AZ1                                   │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Receive and inspect traffic                                  ││
│ │ Stateless: Forward to Stateful Engine (aws:forward_to_sfe)           ││
│ │ Stateful: Match against Suricata rules                               ││
│ │ Result: ✓ PASS (HTTP port 80 allowed by sid:100001)                  ││
│ │ Logging: Flow log entry created in CloudWatch                        ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 5: Firewall Subnet Route Table                                     │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Route inspected traffic to destination                       ││
│ │ Match: Destination 10.0.1.0/24 in VPC                                ││
│ │ Route: Local VPC routing to public subnet                            ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 6: Application Load Balancer (Public Subnet)                       │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Receive HTTP request                                         ││
│ │ Security Group Check:                                                ││
│ │   Rule: Allow TCP 80 from 0.0.0.0/0                                  ││
│ │   Result: ✓ PERMIT                                                   ││
│ │ Load Balancing: Select healthy target (Web Server AZ1 or AZ2)        ││
│ │ Packet Transformation:                                               ││
│ │   SRC=<client-ip> DST=<alb-private-ip> (internal)                    ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 7: ALB Target Group                                                │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Forward to registered target                                 ││
│ │ Health Check: Verify target is healthy (HTTP 200 on /)               ││
│ │ Session: Maintain connection to selected web server                  ││
│ │ Packet: SRC=<alb-private-ip> DST=<web-server-private-ip>:80          ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 8: Web Server (Private Subnet)                                     │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Receive and process HTTP request                             ││
│ │ Security Group Check:                                                ││
│ │   Rule: Allow TCP 80 from ALB Security Group                         ││
│ │   Result: ✓ PERMIT                                                   ││
│ │ Web Server: Apache httpd serves index.html                           ││
│ │ Response: HTTP 200 with HTML content                                 ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│ Total Hops: 8                                                            │
│ Inspection Point: Network Firewall (Hop 4)                               │
│ Security Enforcement: Security Groups at ALB and Web Server              │
└──────────────────────────────────────────────────────────────────────────┘
```

### Egress Traffic Flow: Web Server → Internet

```
┌──────────────────────────────────────────────────────────────────────────┐
│ EGRESS PATH: HTTP Request from Web Server to Internet                    │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Hop 1: Web Server (Private Subnet)                                       │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Initiate outbound connection (e.g., software updates)        ││
│ │ Packet: SRC=10.0.10.x:<random-port> DST=<external-ip>:80             ││
│ │ Security Group: Allow all outbound (0.0.0.0/0)                       ││
│ │ Result: ✓ PERMIT                                                     ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 2: Private Subnet Route Table                                      │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Route to NAT Gateway                                         ││
│ │ Match: Destination 0.0.0.0/0                                         ││
│ │ Route: nat-gateway-az1                                               ││
│ │ Packet: Unchanged                                                    ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 3: NAT Gateway (Public Subnet)                                     │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Perform source NAT translation                               ││
│ │ Translation:                                                         ││
│ │   SRC: 10.0.10.x → <nat-gateway-public-ip>                           ││
│ │   DST: <external-ip>:80 (unchanged)                                  │
│ │ Packet: SRC=<nat-public-ip>:<random-port> DST=<external-ip>:80       ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 4: Public Subnet Route Table                                       │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Route to Network Firewall                                    ││
│ │ Match: Destination 0.0.0.0/0                                         ││
│ │ Route: vpc-endpoint (NFW EP AZ1)                                     ││
│ │ Packet: SRC=<nat-public-ip> DST=<external-ip>                        ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 5: Network Firewall Endpoint AZ1                                   │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Inspect outbound traffic                                     ││
│ │ Stateless: Forward to Stateful Engine (aws:forward_to_sfe)           ││
│ │ Stateful: Match against Suricata rules                               ││
│ │ Result: ✓ PASS (HTTP outbound allowed by sid:100004)                 ││
│ │ Logging: Flow log entry created in CloudWatch                        ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 6: Firewall Subnet Route Table                                     │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Route to Internet Gateway                                    ││
│ │ Match: Destination 0.0.0.0/0                                         ││
│ │ Route: igw                                                           ││
│ │ Packet: Unchanged                                                    ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 7: Internet Gateway                                                │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Forward to internet                                          ││
│ │ Translation: None (NAT already performed)                            ││
│ │ Packet: SRC=<nat-public-ip> DST=<external-ip>                        ││
│ │ Result: ✓ Forwarded to internet                                      ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 8: Internet Destination                                            │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Receive and process request                                  ││
│ │ Response: HTTP response sent back                                    ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│ Total Hops: 8                                                            │
│ NAT Translation: Performed at NAT Gateway (Hop 3)                        │
│ Inspection Point: Network Firewall (Hop 5)                               │
│ Return Path: Response goes through NFW → NAT GW → Web Server            │
└──────────────────────────────────────────────────────────────────────────┘
```

### Return Traffic Flow: Internet → ALB Response Path

```
┌──────────────────────────────────────────────────────────────────────────┐
│ RETURN PATH: HTTP Response from Web Server to Internet Client           │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Hop 1: Web Server                                                        │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Send HTTP response                                           ││
│ │ Packet: SRC=10.0.10.x:80 DST=<alb-private-ip>:<random-port>          ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 2: ALB Target Group                                                │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Return response through ALB                                  ││
│ │ Translation: ALB maintains connection state                          ││
│ │ Packet: SRC=<alb-public-ip>:80 DST=<client-ip>:<random-port>         ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 3: ALB Security Group                                              │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Allow return traffic                                         ││
│ │ Rule: All outbound allowed (0.0.0.0/0)                               ││
│ │ Result: ✓ PERMIT                                                     ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 4: Public Subnet Route Table                                       │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Route to NFW for return inspection                           ││
│ │ Match: Destination <client-ip> (external)                            ││
│ │ Route: vpc-endpoint (NFW EP)                                         ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 5: Network Firewall Endpoint                                       │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Inspect return traffic                                       ││
│ │ Stateful: Response to established connection                         ││
│ │ Result: ✓ PASS (established connection)                              ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 6: Firewall Subnet → IGW                                           │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Route to Internet Gateway                                    │
│ │ Route: 0.0.0.0/0 → igw                                               ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                    │                                     │
│                                    ▼                                     │
│ Hop 7: Internet Gateway                                                │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ Action: Forward response to internet                                 ││
│ │ Result: ✓ Response delivered to client                               ││
│ └──────────────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Security Groups

### ALB Security Group

```
┌──────────────────────────────────────────────────────────────────────────┐
│ SECURITY GROUP: nfw-distributed-demo-alb-sg                              │
│ Attached to: Application Load Balancer                                   │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Ingress Rules:                                                           │
│ ┌──────────────────┬──────────┬─────────────┬──────────────────────────┐│
│ │ Description      │ Protocol │ Port Range  │ Source                   ││
│ ├──────────────────┼──────────┼─────────────┼──────────────────────────┤│
│ │ HTTP from any    │ TCP      │ 80          │ 0.0.0.0/0                ││
│ └──────────────────┴──────────┴─────────────┴──────────────────────────┘│
│                                                                          │
│ Egress Rules:                                                            │
│ ┌──────────────────┬──────────┬─────────────┬──────────────────────────┐│
│ │ Description      │ Protocol │ Port Range  │ Destination              ││
│ ├──────────────────┼──────────┼─────────────┼──────────────────────────┤│
│ │ All outbound     │ All      │ All         │ 0.0.0.0/0                ││
│ └──────────────────┴──────────┴─────────────┴──────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────┘
```

### Web Server Security Group

```
┌──────────────────────────────────────────────────────────────────────────┐
│ SECURITY GROUP: nfw-distributed-demo-web-sg                              │
│ Attached to: EC2 Web Servers in private subnets                          │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Ingress Rules:                                                           │
│ ┌──────────────────┬──────────┬─────────────┬──────────────────────────┐│
│ │ Description      │ Protocol │ Port Range  │ Source                   ││
│ ├──────────────────┼──────────┼─────────────┼──────────────────────────┤│
│ │ HTTP from ALB    │ TCP      │ 80          │ sg-<alb-sg-id>           ││
│ └──────────────────┴──────────┴─────────────┴──────────────────────────┘│
│                                                                          │
│ Egress Rules:                                                            │
│ ┌──────────────────┬──────────┬─────────────┬──────────────────────────┐│
│ │ Description      │ Protocol │ Port Range  │ Destination              ││
│ ├──────────────────┼──────────┼─────────────┼──────────────────────────┤│
│ │ All outbound     │ All      │ All         │ 0.0.0.0/0                ││
│ └──────────────────┴──────────┴─────────────┴──────────────────────────┘│
│                                                                          │
│ Note: Web servers only accept HTTP from ALB, not directly from internet │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Logging and Monitoring

### Network Firewall Logging

```
┌──────────────────────────────────────────────────────────────────────────┐
│ NETWORK FIREWALL LOGGING CONFIGURATION                                   │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Log Destinations:                                                        │
│ ┌─────────────────────────┬──────────────────────────────────────────────┐│
│ │ Log Type                │ Destination                                  ││
│ ├─────────────────────────┼──────────────────────────────────────────────┤│
│ │ ALERT                   │ CloudWatch: /aws/network-firewall/.../alert ││
│ │ FLOW                    │ CloudWatch: /aws/network-firewall/.../flow  ││
│ └─────────────────────────┴──────────────────────────────────────────────┘│
│                                                                          │
│ Log Retention: 7 days                                                    │
│                                                                          │
│ ALERT Logs:                                                              │
│ • Captured when traffic matches alert rules                              │
│ • Includes: timestamp, protocol, src/dst IP:port, action taken           │
│                                                                          │
│ FLOW Logs:                                                               │
│ • Captures all traffic flows through firewall                            │
│ • Includes: connection setup, teardown, bytes transferred                │
└──────────────────────────────────────────────────────────────────────────┘
```

### VPC Flow Logs

```
┌──────────────────────────────────────────────────────────────────────────┐
│ VPC FLOW LOGS CONFIGURATION                                              │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Configuration:                                                           │
│ ┌─────────────────────────┬──────────────────────────────────────────────┐│
│ │ Attribute               │ Value                                        ││
│ ├─────────────────────────┼──────────────────────────────────────────────┤│
│ │ Resource Type           │ VPC (all subnets)                            ││
│ │ Traffic Type            │ ALL (ingress + egress)                       ││
│ │ Destination             │ CloudWatch Logs                              ││
│ │ Log Group               │ /aws/vpc-flow-logs/...                       ││
│ │ Aggregation Interval    │ 60 seconds                                   ││
│ │ IAM Role                │ nfw-distributed-demo-vpc-flow-log-role       ││
│ └─────────────────────────┴──────────────────────────────────────────────┘│
│                                                                          │
│ Log Retention: 7 days                                                    │
│                                                                          │
│ Captured Fields:                                                         │
│ • version, account-id, interface-id, srcaddr, dstaddr                    │
│ • srcport, dstport, protocol, packets, bytes                             │
│ • start, end, action, log-status                                         │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Terraform Resources Reference

| Resource Type | Name | Purpose |
|--------------|------|---------|
| aws_vpc | main | Main VPC (10.0.0.0/16) |
| aws_internet_gateway | main | Internet connectivity |
| aws_subnet | public[0-1] | Public subnets for ALB/NAT GW |
| aws_subnet | firewall[0-1] | Firewall subnets for NFW endpoints |
| aws_subnet | private[0-1] | Private subnets for web servers |
| aws_eip | nat[0-1] | Elastic IPs for NAT Gateways |
| aws_nat_gateway | main[0-1] | NAT Gateways for outbound traffic |
| aws_route_table | igw_edge | IGW edge routing for return traffic |
| aws_route_table | public[0-1] | Public subnet route tables |
| aws_route_table | firewall[0-1] | Firewall subnet route tables |
| aws_route_table | private[0-1] | Private subnet route tables |
| aws_networkfirewall_firewall | main | AWS Network Firewall |
| aws_networkfirewall_firewall_policy | main | Firewall policy |
| aws_networkfirewall_rule_group | stateless | Stateless rule group |
| aws_networkfirewall_rule_group | stateful | Stateful rule group (Suricata) |
| aws_security_group | alb | ALB security group |
| aws_security_group | web | Web server security group |
| aws_lb | main | Application Load Balancer |
| aws_lb_target_group | web | ALB target group |
| aws_lb_listener | http | HTTP listener on port 80 |
| aws_instance | web[0-1] | EC2 web servers |
| aws_iam_role | web_server | IAM role for web servers |
| aws_iam_instance_profile | web_server | Instance profile for SSM |
| aws_cloudwatch_log_group | nfw_alert | NFW alert logs |
| aws_cloudwatch_log_group | nfw_flow | NFW flow logs |
| aws_cloudwatch_log_group | vpc_flow | VPC flow logs |
| aws_flow_log | main | VPC flow logging |

---

## Testing Commands

### Deployment Commands

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# Output the ALB URL
terraform output alb_url
```

### Connectivity Testing

```bash
# Get the ALB URL
ALB_URL=$(terraform output -raw alb_url)

# Test HTTP connectivity through the firewall
curl -v $ALB_URL

# Test with specific headers
curl -H "X-Custom-Header: Test" $ALB_URL

# Follow redirects
curl -L $ALB_URL

# Test with timing
curl -w "@curl-format.txt" -o /dev/null -s $ALB_URL
```

### AWS CLI Validation Commands

```bash
# Verify Network Firewall status
aws network-firewall describe-firewall --firewall-name nfw-distributed-demo-nfw

# Check firewall policy
aws network-firewall describe-firewall-policy --firewall-policy-name nfw-distributed-demo-policy

# List firewall endpoints
aws network-firewall describe-firewall --firewall-name nfw-distributed-demo-nfw \
  --query 'FirewallStatus.SyncStates'

# View route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# Check target group health
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)

# View NFW alert logs (last 5 minutes)
aws logs filter-log-events \
  --log-group-name "/aws/network-firewall/nfw-distributed-demo/alert" \
  --start-time $(date -u -v-5M +%s)000 \
  --limit 10

# View VPC flow logs
aws logs filter-log-events \
  --log-group-name "/aws/vpc-flow-logs/nfw-distributed-demo" \
  --limit 10
```

### SSM Session Manager Access

```bash
# Connect to web server via SSM (no SSH key needed)
aws ssm start-session --target $(terraform output -raw web_server_instance_ids | jq -r '.[0]')

# Once connected, check web server logs
sudo tail -f /var/log/httpd/access_log

# Test outbound connectivity from web server
ping -c 3 8.8.8.8
curl -I https://aws.amazon.com
```

### Load Testing

```bash
# Simple load test with Apache Bench (if installed)
ab -n 1000 -c 10 $(terraform output -raw alb_url)

# Or use curl with parallel requests
for i in {1..100}; do curl -s $ALB_URL > /dev/null & done; wait

# Check ALB metrics in CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=$(terraform output -raw alb_arn | cut -d'/' -f3) \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

---

## Architecture Summary

This distributed AWS Network Firewall architecture provides:

1. **Centralized Traffic Inspection**: All ingress and egress traffic passes through the Network Firewall
2. **Stateful Packet Inspection**: Suricata-compatible rules for deep packet inspection
3. **Multi-AZ High Availability**: Resources distributed across two availability zones
4. **Defense in Depth**: Security groups + Network Firewall + proper routing
5. **Comprehensive Logging**: NFW alert logs, flow logs, and VPC flow logs
6. **No Single Point of Failure**: NAT Gateways and NFW endpoints per AZ

### Security Layers

```
Layer 1: Network Firewall (Stateful/Stateless inspection)
Layer 2: Security Groups (Instance-level firewall)
Layer 3: Route Tables (Network-level access control)
Layer 4: VPC Isolation (Network boundary)
```

### Traffic Inspection Points

- **Inbound**: Internet → IGW → NFW → ALB → Web Server
- **Outbound**: Web Server → NAT GW → NFW → IGW → Internet

All traffic is inspected by the Network Firewall before reaching its destination, ensuring consistent security policy enforcement across the entire VPC.
