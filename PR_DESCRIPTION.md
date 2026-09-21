## 📌 Description

Adds production-ready `ecs-cluster` and `ec2-ecs-service` examples, moves shared infrastructure resources into the root module, and fixes multiple issues discovered during end-to-end testing on AWS.

---

## 🔄 Type of Change

- ✅ 🐛 Bug fix (non-breaking change)
- ✅ ✨ New resource / feature
- ✅ 🔒 Security improvement
- ✅ 📝 Documentation update

---

## 🌍 Terraform Scope

- ✅ New resource added
- ✅ Existing resource updated
- ✅ Variable(s) modified
- ✅ Output(s) modified
- ✅ Examples / usage updated

---

## ✅ Checklist

- ✅ Code follows Terraform best practices
- ✅ `terraform fmt -recursive` and `terraform validate` have been executed
- ✅ `terraform plan` has been reviewed and changes are expected
- ✅ Changes are backward compatible
- ✅ Variables and outputs are properly defined and documented
- ✅ No sensitive data (secrets, credentials, keys) is exposed

---

## 🧩 Terraform Version & Providers

**Terraform Version:** `>= 1.16.1`
**Provider(s):** `hashicorp/aws ~> 5.x`, `hashicorp/tls`, `hashicorp/local`

---

## 🧪 Testing

- ✅ Tested locally using `terraform plan` / `apply`
- ✅ Tested in a sandbox environment

**Test Details:**
- `examples/ecs-cluster`: `terraform apply` and `terraform destroy` completed successfully without manual intervention
- EC2 instances registered in ECS cluster automatically after apply
- No public IPs assigned to EC2 instances
- ALB correctly routes `/apache*` to Apache service and default to Nginx service

---

## 📸 Screenshots / Documentation

See `examples/ecs-cluster/` and `examples/ec2-ecs-service/` for full usage.

---

## 🔗 Related Issues

Closes #

---

## 📝 Additional Notes

**Root Module (`main.tf`, `variables.tf`, `outputs.tf`)**
- Added SSH key pair generation and local `.pem` file output
- Added ECS capacity provider with managed scaling linked to external ASG
- Added `managed_draining = "DISABLED"` to prevent lifecycle hook blocking `terraform destroy`
- Added `aws_iam_role_policy` for Secrets Manager access on task execution role
- Added `create_alb`, `secrets_manager_policy_enabled`, `capacity_provider_enabled`, `autoscaling_group_arn` variables

**`examples/ecs-cluster`**
- New example: VPC, subnets, security groups, KMS key, IAM role, ECS cluster, EC2 ASG
- Moved ASG to private subnets (`associate_public_ip_address = false`)
- Added `create_alb = false` to prevent duplicate internal ALB
- Added `vpc_cidr_block` output
- Restricted SSH SG to VPC CIDR
- Scoped KMS key policy to account root ARN
- Added `AWSServiceRoleForAutoScaling` grants to KMS key policy for EBS encryption
- Added `private_inbound/outbound_acl_rules` — private subnet NACLs were deny-all
- Simplified `user_data` to write `ecs.config` before ECS agent starts

**`examples/ec2-ecs-service`**
- New example: nginx + apache sharing a single ALB with path-based routing
- Uses `terraform_remote_state` to reference `ecs-cluster` outputs
- Fixed `cidr_ipv4` — was set to VPC ID instead of CIDR block

**`modules/service`**
- Fixed `create_alb = false` to correctly skip internal ALB and target group creation

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| `terraform destroy` stuck on IGW | EC2 instances had public IPs mapped | Moved ASG to private subnets |
| `terraform destroy` stuck on ASG | ECS managed draining lifecycle hook (3600s) | `managed_draining = "DISABLED"` |
| `InvalidKMSKey.InvalidState` | `AWSServiceRoleForAutoScaling` missing from KMS policy | Added required KMS grants |
| ECS agent not registering | Private subnet NACL was deny-all | Added NACL allow rules |
| Duplicate internal ALB | `create_alb` defaulted to `true` | Added `create_alb = false` |
| `cidr_ipv4` validation error | VPC ID passed instead of CIDR | Fixed to use `vpc_cidr_block` |
