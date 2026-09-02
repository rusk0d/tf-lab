# AWS VPC + Orphan Resource Scanner

A two-availability-zone VPC built with Terraform, plus a containerised Python tool that
audits an AWS account for resources that are costing money without doing anything.

I built this to learn AWS networking and infrastructure as code properly rather than
through tutorials. Everything here I wrote myself and can explain.

## What it does

**The infrastructure** is a standard two-AZ VPC: public and private subnets in each zone,
an internet gateway, a NAT gateway, route tables, security groups, and an IAM role for the
scanner instance.

**The scanner** runs inside the private subnet and reports on:

- Unattached Elastic IPs
- Security groups not attached to any network interface and not referenced by other groups
- EBS volumes in the `available` state
- Running EC2 instances

It runs as a Docker container pulled from ECR, using credentials from an EC2 instance role.
No static credentials anywhere.

## Architecture

```
VPC 10.0.0.0/16
├── eu-central-1a
│   ├── public  10.0.1.0/24   ← NAT gateway, bastion
│   └── private 10.0.11.0/24  ← scanner instance
└── eu-central-1b
    ├── public  10.0.2.0/24
    └── private 10.0.12.0/24

Internet gateway → attached to VPC
Route tables → public: 0.0.0.0/0 to IGW
               private: 0.0.0.0/0 to NAT
```

## Decisions

**One NAT gateway, not two.** Two would be the resilient answer — if `1a` fails, the private
subnet in `1b` loses outbound connectivity, since its route points at a NAT that no longer
exists. I chose one because a NAT gateway is the most expensive thing in this stack at around
$35/month and this is a lab. In production I would run one per AZ.

**The scanner runs on EC2, but Lambda would be the right choice.** The job takes about five
seconds and runs on demand. Paying for an instance to sit idle the rest of the time makes no
sense — a scheduled Lambda, or an ECS task on Fargate if the container image mattered, would
be cheaper and require no host to patch. I used EC2 deliberately because the point was to
learn Docker rather than to build the cheapest thing.

**Least-privilege IAM.** The instance role grants five specific `ec2:Describe*` actions and
four ECR actions rather than the managed `ReadOnlyAccess` policy, which would grant several
hundred. `Resource: "*"` is unavoidable here because EC2 describe actions do not support
resource-level permissions.

**`depends_on` for the NAT gateway.** The private instance's `user_data` needs outbound
internet to install Docker and pull from ECR. Nothing in the configuration references the NAT
gateway from the instance, so Terraform could not infer the ordering and would sometimes
create the instance first. This is one of the few cases where an explicit dependency is
correct.

**Security group checks look at attachments, not the group.** There is no field on a security
group that says whether it is in use. The check builds a set of every group ID attached to a
network interface, plus every group ID referenced in another group's rules, and reports
anything in neither. The naive version — listing groups and guessing — produces false
positives that would break rules if someone acted on them.

## Container notes

The Dockerfile installs dependencies before copying application code, so editing the script
does not invalidate the pip layer. It runs as a non-root user. The base image is
`python:3.12-slim` rather than `python:3.12`, which is roughly 150MB instead of about 1GB.

ECR image scanning is enabled. The scan reports several critical CVEs in `perl` and `glibc`
from the Debian base layer — none of them reachable from a Python script making read-only API
calls with no untrusted input. A distroless base image would eliminate that class of finding
entirely and is what I would use if this ran anywhere real.

## Running it

```bash
terraform init
terraform plan
terraform apply
```

You will need `terraform.tfvars` with your own values:

```hcl
my_ip = "x.x.x.x"
```

The SSH security group is scoped to that address rather than `0.0.0.0/0`.

Build and push the scanner image:

```bash
docker build -t orphan-scanner .
aws ecr get-login-password --region eu-central-1 \
  | docker login --username AWS --password-stdin <account>.dkr.ecr.eu-central-1.amazonaws.com
docker tag orphan-scanner:latest <ecr-url>:latest
docker push <ecr-url>:latest
```

The ECR repository is created by Terraform, so apply before pushing.

**Destroy when finished.** The NAT gateway bills hourly whether or not anything is using it:

```bash
terraform destroy
```

## What I would change

- Move the scanner to a scheduled Lambda and drop the EC2 instance, the bastion, and the NAT
  gateway entirely. The whole stack would then cost nothing at rest.
- Replace the hardcoded AMI ID with an `aws_ami` data source, since AMI IDs differ per region
  and change with each release.
- Use SSM Session Manager instead of a bastion. No keys, no inbound rules, no public instance.
- Add remote state in S3 with DynamoDB locking. Local state is fine for one person but does
  not survive a second.
