# 🎯 Viva & Interview Master Guide — `image-service-infra`

> **Project:** Real-time Image Processing & Gallery Service (Infra-as-Code)
> **Repo:** `image-service-infra`
> **Stack:** Terraform 1.16+ · AWS Provider ~6.0 · Region `eu-north-1` (Stockholm)
> **Author:** Ali
> **Purpose:** Everything an examiner/interviewer can ask about this repo + every AWS service used here explained in simple words.

---

## 📖 How to use this file

| If you have... | Read... |
| :--- | :--- |
| 5 minutes before viva | **Part 1** (60-second pitch) + **Part 2** (best answers) |
| 30 minutes | **Part 1 → Part 6** |
| A full day | Whole file, top to bottom |

**Golden rule for answering:** *Definition → Why we used it → How it is wired in THIS repo → Trade-off.*
Every strong answer has those 4 moves. Memorise the pattern, not the words.

Legend used in this file:

- ⭐ **Important point** — likely to be asked.
- ⚠️ **Trap / gotcha** — a place where candidates slip.
- 💡 **Pro tip** — shows senior-level thinking.
- 🎤 **Say this in the viva** — ready-to-speak phrasing.

---

# PART 0 — Project at a glance (know this cold)

## 0.1 What the system does

Users log in, upload images from the browser, the image goes **directly to S3** (not through the backend), a **Lambda** compresses it, tells the **backend**, the backend saves the status in **PostgreSQL** and pushes a **real-time notification (Socket.IO/WebSocket)** to the browser.

**End-to-end flow (memorise this line):**

```
Browser → ALB → Backend (gets presigned URL)
Browser → S3  (uploads directly to uploads/)
S3 event → Lambda (compress with Sharp) → writes processed/
Lambda → Backend  POST /internal/images/events (x-api-key)
Backend → RDS (status = PROCESSED)  → Socket.IO → Browser shows "done"
Browser → Backend (asks for presigned download URL) → S3 (download)
```

## 0.2 The 4 repositories (not just this one)

| Repo | Role | Deployed where |
| :--- | :--- | :--- |
| `image-service-infra` | **This repo** — all AWS infra in Terraform | AWS (via GitHub Actions OIDC) |
| `image-service-backend` | NestJS REST API + WebSocket + Prisma | ECS Fargate (port 3001) |
| `image-service-frontend` | Next.js 15 app | ECS Fargate (port 3000) |
| `image-processor-lambda` | Node 20 + Sharp image compressor | AWS Lambda (container image) |

## 0.3 Infrastructure inventory (what the Terraform actually builds)

| # | AWS Resource | Terraform module | Key settings in this repo |
| :--- | :--- | :--- | :--- |
| 1 | **VPC** | `modules/vpc` | `10.0.0.0/16`, 2 AZs, DNS hostnames on |
| 2 | Public subnets ×2 | `modules/vpc` | `cidrsubnet(...,4,0..1)` → `/20` each |
| 3 | Private subnets ×2 | `modules/vpc` | `cidrsubnet(...,4,4..5)` → `/20` each |
| 4 | Internet Gateway | `modules/vpc` | For public subnets |
| 5 | NAT Gateway | `modules/vpc` | **1 only** in dev (`single_nat_gateway = true`) |
| 6 | Elastic IP | `modules/vpc` | Attached to NAT |
| 7 | Route tables | `modules/vpc` | Public → IGW, Private → NAT |
| 8 | **S3 Gateway VPC Endpoint** | `modules/vpc` | Lets private ECS reach S3 without NAT |
| 9 | **S3 bucket (images)** | `modules/s3` | `image-service-dev-images-<account-id>` |
| 10 | **S3 bucket (state)** | `bootstrap/` | `image-service-tfstate-10-2026`, versioned |
| 11 | **ECR** ×3 repositories | `modules/ecr` | backend, frontend, `image-processor/lambda` |
| 12 | **RDS PostgreSQL 16** | `modules/rds` | `db.t4g.micro`, gp3, encrypted, private |
| 13 | DB subnet group | `modules/rds` | Uses the 2 private subnets |
| 14 | **ALB** (internet-facing) | `modules/alb` | HTTP:80, path-based routing |
| 15 | Target groups ×2 | `modules/alb` | backend (sticky), frontend |
| 16 | Listener + rules | `modules/alb` | `/auth/*`, `/images/*`, `/internal/*`, `/health`, `/socket.io/*` |
| 17 | **ECS Cluster** | `modules/ecs` | Fargate |
| 18 | Task definitions ×2 | `modules/ecs` | awsvpc network mode |
| 19 | ECS services ×2 | `modules/ecs` | desired_count from var, circuit breaker |
| 20 | ECS task + execution roles | `modules/ecs` | Separate role per service |
| 21 | CloudWatch log groups | `modules/ecs`, `modules/lambda` | retention 14 days |
| 22 | **Lambda** (container) | `modules/lambda` | S3 trigger on `uploads/` |
| 23 | Lambda permission + S3 notification | `modules/lambda` | `s3:ObjectCreated:*` |
| 24 | **Secrets Manager** secrets | `envs/dev` | `callback`, `app`, plus RDS-managed |
| 25 | **GitHub OIDC provider** | `modules/github-oidc` | No static AWS keys |
| 26 | IAM roles ×5 (OIDC) | `modules/github-oidc` | infra-plan, infra-apply, backend, frontend, lambda |
| 27 | Security groups + rules | `vpc`/`alb`/`ecs`/`rds` | Chained: Internet→ALB→ECS→RDS |

⚠️ **Note:** `modules/sqs` exists but is an **empty stub** (planned for `NOTIFY_MODE=sqs`). Be honest if asked — say *"designed but not implemented; the Lambda supports an SQS mode but we run in API mode."*

## 0.4 Naming conventions used

- `local.name_prefix = "${var.project}-${var.environment}"` → **`image-service-dev`**
- Images bucket: `${name_prefix}-images-${account_id}` → always **globally unique**.
- Default tags on everything via provider: `Project`, `Environment`, `ManagedBy=terraform`, `Repo=image-service-infra`.

⭐ **Why the account ID in the bucket name?** S3 bucket names are **globally unique across all AWS accounts on Earth**. Adding the account ID avoids collisions.

## 0.5 State & locking

- Remote backend = **S3** (`image-service-tfstate-10-2026`), key `dev/terraform.tfstate`, `encrypt = true`.
- **State locking = `use_lockfile = true`** (native S3 lockfile, Terraform ≥ 1.10). No DynamoDB table needed anymore.

⚠️ **Classic trap question:** *"How do you lock Terraform state?"*
Old answer: **DynamoDB table**. New answer for this repo: **S3 native lockfile (`use_lockfile = true`)** — DynamoDB is no longer required.

## 0.6 The "Zero Static Keys" strategy (headline story of this project)

| Place | How it authenticates | Key idea |
| :--- | :--- | :--- |
| Laptop (bootstrap) | **IAM Identity Center (SSO)** | `aws sso login`, no long-lived keys |
| GitHub Actions → AWS | **OIDC federation** | Short-lived tokens, trust policy locked to repo + branch |
| ECS task → S3/Secrets | **ECS task role** | SDK picks up credentials automatically |
| Lambda → S3/backend | **Lambda execution role** | No keys in code |
| RDS password | **`manage_master_user_password`** | AWS creates & rotates via Secrets Manager |
| Lambda → backend | **Shared secret in Secrets Manager** | Not in env vars / not in Git |

🎤 **Say this:** *"There is not a single long-lived AWS access key in the whole project. Every machine identity uses a temporary credential issued automatically."*

---

# PART 1 — The 60-second pitch + answer framework

## 1.1 60-second pitch (memorise)

> "It's a real-time image processing and gallery platform on AWS. Users upload images, and the work is split across two compute models. The **frontend (Next.js)** and **backend (NestJS)** run as containers on **ECS Fargate** behind an **Application Load Balancer** with path-based routing. The image compression is event-driven: the browser uploads directly to **S3** using a **presigned URL**, S3 fires an event, a containerised **Lambda** compresses the image with Sharp, then calls the backend which updates **RDS PostgreSQL** and pushes a **WebSocket** notification to the browser. Everything — VPC, subnets, NAT, S3, ECR, RDS, ALB, ECS, Lambda, IAM — is built from scratch with **modular Terraform**. There are **no static AWS keys anywhere**: CI/CD uses **GitHub OIDC**, ECS uses **task roles**, Lambda uses its **execution role**, and the DB password is **managed by AWS Secrets Manager**."

## 1.2 The 4-move answer framework

1. **Definition** — what is it, in one plain sentence.
2. **Why here** — the reason this repo chose it.
3. **How wired** — which file/module and which settings.
4. **Trade-off** — what it costs or costs you in complexity.

## 1.3 The "why did you do X" cheat sheet

| Decision | One-line justification |
| :--- | :--- |
| Lambda for image work | CPU-heavy, spiky, event-driven → pay only when used; auto-scales |
| ECS Fargate for API/UI | Long-running, needs WebSocket → containers, no servers to patch |
| ALB not API Gateway | Cheaper for containers, native WebSocket, direct ECS target groups |
| Presigned URLs | Backend never touches the image bytes → no bandwidth bottleneck |
| S3 event trigger | Native, no polling, no queue needed in API mode |
| Single NAT in dev | Cost saving (NAT ≈ $0.045/hr + data); prod uses one per AZ |
| Path-based routing | One DNS name for frontend + backend, no awkward ports |
| Sticky sessions on backend | WebSocket/Socket.IO is stateful, must hit the same task |
| S3 Gateway Endpoint | Private tasks reach S3 without NAT data charges |
| OIDC instead of keys | Nothing to leak, rotate, or store in GitHub Secrets |

---

# PART 2 — Terraform & IaC viva (repo-specific, high probability)

⭐ These are the **most likely first questions** because the whole repo is Terraform.

### Q1. What is Terraform and why did you not just click in the AWS Console?
**A:** Terraform is an **Infrastructure as Code (IaC)** tool — you describe the desired infrastructure in text (`.tf` files) and it creates it. Console clicking is manual, unrepeatable and undocumented. With Terraform the whole environment can be recreated (`destroy` then `apply`), version-controlled in Git, reviewed in Pull Requests, and reused across dev/prod with different variables. Also console changes cause **drift (a mismatch between reality and code)**.

💡 **Pro tip:** "My rule is: if it isn't in code, it doesn't exist."

### Q2. Explain the folder structure of this repo.
**A:**
```
image-service-infra/
├── bootstrap/          # one-time: creates the S3 bucket that stores Terraform state
├── modules/            # reusable building blocks
│   ├── vpc/ ecr/ rds/ s3/ alb/ ecs/ lambda/ github-oidc/ sqs(stub)
└── envs/
    └── dev/            # wires the modules together for one environment
        ├── backend.tf  # remote state
        ├── providers.tf# terraform + provider versions, default_tags
        ├── main.tf     # vpc, ecr, s3, rds
        ├── compute.tf  # alb + ecs + RDS glue security-group rule
        ├── lambda.tf   # lambda + callback secret
        ├── oidc.tf     # github OIDC roles
        ├── secrects.tf # app secret (jwt_secret)
        ├── locals.tf   # name_prefix, account id, state bucket name
        ├── variables.tf, outputs.tf, terraform.tfvars
```
⭐ **Key idea: `modules/` = "what to build", `envs/` = "how to configure it for one environment".** Prod would be a new folder `envs/prod` calling the same modules.

### Q3. Why modules instead of one big `main.tf`?
**A:** Reusability, separation of concerns, and safer changes. Each module has one job and a clean **interface (variables in, outputs out)**. If I change how VPCs are built, I change one folder instead of copy-pasting. It also makes the code reviewable — a reviewer can see the contract of a module without reading every line.

### Q4. What is a "module" in Terraform, precisely?
**A:** A module is just **a folder of `.tf` files** that is called with a `module "x" { source = "..." }` block. A `source` can be local (`../../modules/vpc`), from the registry, or from Git. Inputs = `variable`, outputs = `output`. The root module is the folder where you run `terraform apply` (here `envs/dev`).

### Q5. What is Terraform state and why is it so important?
**A:** State (`terraform.tfstate`) is a **JSON file that remembers what Terraform has already created** and maps each `.tf` resource to a real cloud resource ID. Without it Terraform would not know what exists and would try to re-create everything. It can contain secrets, so it must be **stored remotely, encrypted, and locked** (which is exactly what `backend.tf` does).

⚠️ **Never commit the state file to Git.** This repo's `.gitignore` excludes `*.tfstate` — good practice.

### Q6. Why remote state (S3) instead of local state?
**A:** Team collaboration, safety and locking. S3 state lets several engineers/CI jobs share one source of truth, encrypts it at rest, versions it (bootstrap enables **versioning**), and with `use_lockfile = true` prevents two applies from running at once. Local state would be lost or conflict.

### Q7. How does state locking work here?
**A:** `use_lockfile = true` — Terraform writes a lock object next to the state file in S3 so a second `apply` waits or fails instead of corrupting state. Historically people used a **DynamoDB table** for this; the lockfile approach is the modern, simpler way.

### Q8. What is the `bootstrap` folder and why is it separate?
**A:** It solves a **chicken-and-egg problem**: to store state in S3 you need an S3 bucket, but that bucket also needs state. So `bootstrap` creates the state bucket once, and its own tiny state lives in that same bucket (`key = "bootstrap/terraform.tfstate"`). It is run rarely and locally. It enables **versioning**, **encryption**, **public access block** and sets `prevent_destroy`.

### Q9. `count` vs `for_each` — where did you use each and why?
**A:**
- **`count`** — used for identical resources that just differ by index (e.g. `aws_subnet.public[count.index]`, NAT, route tables).
- **`for_each`** over a `map`/`set` — used when each instance has a **stable identity/name**: ECR repos, ECS services, IAM roles, target groups.

⭐ **Rule:** use `count` only for identical clones; use `for_each` when removing one item in the middle should not re-number everything. With `count`, deleting index 0 shifts every other resource → Terraform destroys and recreates things. `for_each` avoids that.

### Q9b. Where do you use `for_each` in this repo?
`aws_ecr_repository.this` (set of repo names), `aws_ecs_task_definition/service`, `aws_iam_role.task`, `aws_lb_target_group.this` (map of services), `aws_cloudwatch_log_group.this`, `github_oidc` roles map.

### Q10. What is the difference between `count` and `for_each` when a list changes?
⭐ Already covered — `for_each` keys are stable, so removing an item only touches that one item. `count` shifts indexes and can destroy/recreate unrelated resources. **This is a favourite interview question.**

### Q11. `variable`, `local`, `output` — what's the difference?
- **variable** = input to a module (can be overridden, has a type/default/validation).
- **local** = a computed internal value, not overridable (`name_prefix`, `account_id`).
- **output** = value a module exposes to its caller (or to the CLI), e.g. `module.vpc.vpc_id`.

### Q12. What is a `data` source? Give examples from this repo.
**A:** A `data` block **reads existing information** without creating anything. Examples:
- `data "aws_caller_identity" "current"` → account ID.
- `data "aws_availability_zones" "available"` → real AZ names for the region (never hardcode AZs!).
- `data "aws_iam_policy_document"` → builds least-privilege policies in JSON safely.

⭐ **Why not hardcode AZs?** AZ names can differ between accounts; the `data` source guarantees valid ones. We `slice(..., 0, 2)` to take exactly two AZs.

### Q13. What is `cidrsubnet()` and how are subnets calculated here?
**A:** `cidrsubnet("10.0.0.0/16", 4, n)` adds 4 bits of "new subnet" space → each subnet is a `/20`.
- public: n=0 → `10.0.0.0/20`, n=1 → `10.0.16.0/20`
- private: n=4 → `10.0.64.0/20`, n=5 → `10.0.80.0/20`
A `/20` = 4096 addresses (4091 usable — AWS keeps 5). ⭐ Using a function instead of writing IPs by hand avoids overlaps and human error.

### Q14. What does `terraform fmt`, `validate`, `plan`, `apply`, `destroy` do?
| Command | Meaning |
| :--- | :--- |
| `fmt` | Formats code to canonical style (run before commit) |
| `validate` | Checks syntax and internal consistency |
| `plan` | Shows what *would* change — read-only, safe |
| `apply` | Executes the plan and creates/updates resources |
| `destroy` | Deletes everything in state (⚠️ dangerous) |

### Q15. How do you handle secrets in Terraform?
**A:** Never hardcode. Secrets come from **Secrets Manager** (read by applications at runtime), not into `.tf` or `.tfvars`. `.gitignore` excludes `*.tfvars`. The DB password uses `manage_master_user_password = true` so AWS owns it entirely. For local use we authenticate with **SSO**, not stored keys.

### Q16. What are `default_tags` and why use them?
**A:** In `providers.tf` under the `aws` provider, `default_tags` applies `Project`, `Environment`, `ManagedBy`, `Repo` to **every** taggable resource automatically. This is for **cost allocation, ownership and automation** — you can filter the AWS bill by `Project` or find anything Terraform made.

### Q17. What is the `lifecycle` block and where is it used?
**A:** It controls how Terraform treats a resource:
- `create_before_destroy = true` (used on security groups & DB) → create the replacement before deleting the old, avoiding downtime.
- `prevent_destroy = true` (used on the state bucket) → Terraform refuses to delete it. ⭐ Protects against accidental `destroy`.
- `ignore_changes = [image_uri]` (used on Lambda) → Terraform ignores the image URI because CI/CD updates the image, so Terraform shouldn't fight it.
- `depends_on` — explicit ordering, e.g. the S3 bucket policy waits for the public access block.

### Q18. What is a validation block? Show one.
**A:** It fails early with a helpful error instead of a confusing AWS API error. Examples: `environment` must be `dev` or `prod`; `architecture` must be `x86_64` or `arm64`; `default_service` must be a key inside `services`; RDS subnet list must have ≥ 2 subnets.

### Q19. How would you add a `prod` environment?
**A:** Copy `envs/dev` → `envs/prod`, change `terraform.tfvars` (environment, `db_multi_az = true`, `db_deletion_protection = true`, `single_nat_gateway = false`, `allow_force_destroy = false`, larger instance class), point the backend key to `prod/terraform.tfstate`, and reuse every module unchanged. ⭐ **That is the whole point of modules.**

### Q20. What does `terraform.tfstate` contain and why lock it down?
**A:** Resource IDs, attributes, and **often secrets in plain text** (passwords, keys). It lives in a **private, encrypted, versioned** S3 bucket with public access blocked and TLS-only policy (see bootstrap). Access is scoped by IAM (`plan_state_lock` policy allows only the state object).

---

# PART 3 — AWS services: general concepts + project usage

Each service is covered as: **What it is → Concepts → Q&A → Practice this repo uses → Use cases.**

---

## 3.1 IAM (Identity and Access Management) 🔑

### What it is
The **security guard of AWS** — it decides *who* can do *what* on *which resource*. Nothing in AWS happens without IAM allowing it.

### Core concepts
- **User** = a person/entity with long-term credentials (⚠️ we avoid these).
- **Role** = an identity assumed temporarily; great for services and CI.
- **Policy** = a JSON document of Allow/Deny rules (`Effect`, `Action`, `Resource`, `Condition`, `Principal`).
- **Identity-based policy** = attached to a role/user.
- **Resource-based policy** = attached to a resource (e.g. S3 bucket policy, Lambda permission).
- **Trust policy** = *who is allowed to assume this role* (`sts:AssumeRole` / `AssumeRoleWithWebIdentity`).
- **Least privilege** = give the minimum permissions needed.

### Q&A
**Q: Role vs User?**
**A:** A user has permanent credentials; a role is assumed temporarily and returns short-lived credentials. We use roles everywhere — no users with keys.

**Q: What is an "assume role"?**
**A:** An AWS identity or external identity calls STS (Security Token Service) and exchanges its identity for **temporary credentials** for the role. GitHub does this via OIDC; ECS tasks do it automatically.

**Q: Difference between the two ECS roles?**
⭐ Very common question.
- **Execution role** — used by the **ECS agent** (the platform): pull the image from ECR, write logs to CloudWatch, inject secrets from Secrets Manager.
- **Task role** — used by the **application code** inside the container (e.g. backend reading/writing S3).
Mixing them up is a classic mistake: "image won't pull / logs missing" → execution role. "App gets AccessDenied calling S3" → task role.

**Q: How is IAM used in this repo?**
| Role | Purpose |
| :--- | :--- |
| `AmazonECSTaskExecutionRolePolicy` (managed) | ECR pull + logs for ECS |
| `${name_prefix}-{service}-task` | App code → S3 (backend), etc. |
| `${name_prefix}-image-processor-exec` | Lambda → S3 + Secrets + logs |
| `github_oidc` ×5 | CI/CD → AWS with no keys |
| RDS managed secret | DB user/password |

**Q: What is a managed vs inline policy?**
**A:** Managed = standalone, reusable, can be AWS-provided or customer-created. Inline = embedded inside one role, deleted with it. We use AWS managed policies where they fit (`AdministratorAccess`, `ReadOnlyAccess`, `AmazonECSTaskExecutionRolePolicy`) and inline `aws_iam_policy_document` for precise least-privilege.

💡 **Pro tip:** The `infra-apply` GitHub role uses `AdministratorAccess`. That's fine for a solo portfolio project, but explain the improvement: *"in a real team I'd scope it to only the resource types Terraform manages and add a permissions boundary."* Examiners love that honesty.

### Use cases of IAM
Access control for every AWS service, cross-account access, service-to-service auth, CI/CD keyless deploy, S3 object-level isolation.

---

## 3.2 VPC & Networking 🌐

### What it is
**VPC (Virtual Private Cloud)** = your own isolated private network inside AWS. Like having a private data-centre network in the cloud.

### Core concepts
- **CIDR block** = the IP range (`10.0.0.0/16` = 65,536 addresses).
- **Subnet** = a slice of the VPC tied to **one Availability Zone (AZ)**.
- **Public subnet** = has a route to an **Internet Gateway (IGW)** → reachable from internet.
- **Private subnet** = no direct internet route; outbound goes through **NAT Gateway**. This is where servers/databases live.
- **Internet Gateway (IGW)** = the door between your VPC and the internet (bidirectional, one per VPC).
- **NAT Gateway** = one-way door **out** for private subnets (they can download updates, but internet can't reach them). Lives in a public subnet, needs an Elastic IP.
- **Route Table** = rules saying "traffic to this CIDR goes to this gateway".
- **Availability Zone (AZ)** = physically separate data centre in a region. Spreading across ≥2 AZs = high availability.
- **Security Group (SG)** = **stateful (remembers established connections)** firewall at the resource level. Allow-only.
- **Network ACL (NACL)** = **stateless (must allow traffic both directions)** firewall at the subnet level. Supports deny.
- **VPC Endpoint** = private connection to an AWS service without the public internet.
  - **Gateway endpoint** (used here for S3) = works via route table, free.
  - **Interface endpoint (PrivateLink)** = an ENI (network interface) in your subnet, billed hourly.

### Q&A
**Q: Explain the VPC design in this repo.**
**A:** A `/16` VPC in `eu-north-1` across 2 AZs. Each AZ gets one public and one private `/20` subnet. Public subnets host the ALB and NAT gateway; private subnets host ECS tasks and RDS. Public route table sends `0.0.0.0/0` to the IGW; private route tables send `0.0.0.0/0` to the NAT. A **Gateway endpoint for S3** is attached to the private route tables.

**Q: Why are ECS and RDS in private subnets?**
**A:** Defence in depth. They must not be directly reachable from the internet. Only the ALB (public) can talk to ECS, and only ECS can talk to RDS. If someone finds the ECS task IP, they still can't reach it from outside.

**Q: Why public + private subnets in each AZ?**
**A:** A subnet belongs to exactly one AZ, so to be resilient you need at least two AZs, and each AZ needs both tiers. If one AZ fails, the other keeps serving.

**Q: Why one NAT gateway in dev but more in prod?**
**A:** Cost vs availability trade-off. NAT costs ~**$0.045/hour (~$32/month)** plus data processing. One NAT = cheap but a **single point of failure** for outbound traffic. Prod uses one NAT per AZ (`single_nat_gateway = false`) so an AZ failure doesn't kill egress.

**Q: What is the S3 Gateway endpoint doing here, and why does it matter?**
⭐ Great cost question.
**A:** Private ECS tasks need to read/write S3. Without the endpoint they'd go ECS → NAT → Internet → S3, paying **NAT data-processing charges**. The Gateway endpoint routes S3 traffic *inside* AWS for **free**, keeps it off the public internet, and reduces NAT load.

**Q: Security Group vs NACL?**
| | Security Group | NACL |
| :--- | :--- | :--- |
| Level | Instance/ENI | Subnet |
| State | Stateful | Stateless |
| Rules | Allow only | Allow + Deny |
| Evaluation | All rules together | In order |

**Q: How do the security groups chain in this repo?**
⭐ Favourite diagram question.
```
Internet → ALB SG (allow 80 from 0.0.0.0/0)
ALB SG → ECS SG (allow service ports from ALB SG)   [SG referencing, not IP!]
ECS SG → RDS SG (allow 5432, referenced from ECS SG) [rule defined in compute.tf]
```
💡 We reference the **security group ID** (`referenced_security_group_id`), not an IP range — so it keeps working when IPs change. This is the correct pattern.

**Q: Why does RDS have no ingress rule inside its module?**
**A:** Deliberate decoupling. The `rds` module stays generic; the **glue rule** lives in `compute.tf` (`rds_from_ecs`) because it connects two modules. ⭐ This is dependency inversion — modules shouldn't know about each other.

**Q: What's a VPC endpoint type we're missing, and why?**
**A:** ECS tasks also pull from **ECR**, read **Secrets Manager**, and write **CloudWatch Logs** — those still use NAT. Adding **Interface endpoints** for `ecr.api`, `ecr.dkr`, `secretsmanager`, `logs` would cut NAT data cost and remove internet dependency (trade-off: hourly per-endpoint charge, and 2 endpoints to cover ECR).

**Q: What is "cross-AZ data transfer cost"?**
**A:** AWS charges for data crossing AZ boundaries. With 2 ECS tasks split across AZs and one shared NAT, some traffic crosses AZs. Dev runs 1 task each, so it's minimal; at scale you balance cost vs resilience.

### Use cases of VPC
Network isolation, multi-tier apps, hybrid connectivity (VPN/Direct Connect), private access to AWS services, compliance boundaries.

---

## 3.3 S3 (Simple Storage Service) 🗄️

> ⭐ **This is the service the user specifically asked about — the CORS question lives here.**

### What it is
**Object storage** — files ("objects") stored inside "buckets" over HTTP. Effectively infinite, ~11 nines of durability (99.999999999%). Not a filesystem and not a database; it's a giant key-value store for bytes.

### Core concepts
- **Bucket** = top-level container. Name is **globally unique across all AWS** and lowercase.
- **Object** = a file + metadata, identified by a **key** (the full path, e.g. `uploads/abc.jpg`).
- **Prefix** = the "folder" part of a key (`uploads/`). S3 has no real folders — they're just name prefixes.
- **Versioning** = keeps every version of an object (protects against overwrite/delete). **Used in the state bucket**, off for the images bucket.
- **Storage class** = how fast/cheap the object is (see Glacier below).
- **Durability vs Availability** = durability = won't lose data; availability = can you read it right now.
- **Presigned URL** = a temporary, signed URL that grants time-limited access to one object without making the bucket public.
- **Multipart upload** = splitting a big file into parts for reliable/resumable uploads.
- **Lifecycle rule** = automated actions over time (move to Glacier, delete old versions, abort incomplete uploads).
- **Server-side encryption (SSE)** = S3 encrypts data at rest:
  - **SSE-S3** (`AES256`) = AWS-managed keys → what this repo uses.
  - **SSE-KMS** = your KMS key, audit trail, more control, small cost.
  - **SSE-C** = you supply the key.
- **Public Access Block** = 4 settings that stop any public access. Enabled here.
- **Bucket policy** = resource-based JSON policy on the bucket.
- **CORS** = Cross-Origin Resource Sharing (see deep dive below).

### Q&A

**Q: How many S3 buckets exist in this project?**
⭐ Direct question the user asked.
**A:** **Two per environment:**
1. **Terraform state bucket** — `image-service-tfstate-10-2026` (created by `bootstrap/`, versioned, encrypted, public-access-blocked, `prevent_destroy`).
2. **Images bucket** — `image-service-dev-images-<account-id>` (created by `modules/s3`, stores `uploads/` and `processed/`).

So: **2 buckets in the dev environment.** If asked "how many for the application itself?" → **1** (the images bucket). If prod is added, the count grows (separate state key or bucket + a prod images bucket).

**Q: What is the URL doing inside the CORS policy?**
⭐ Direct question the user asked — answer carefully.
**A:** The `AllowedOrigins` value is a **web origin**, i.e. `scheme + domain + port` (e.g. `http://image-alb-123.eu-north-1.elb.amazonaws.com`). It is **not** the bucket URL.

*Why it exists:* Browsers enforce the **Same-Origin Policy** — a page loaded from `origin A` cannot read a response from `origin B` unless `origin B` explicitly allows it. Our page is served from the ALB domain, but the upload/download target is `s3.amazonaws.com`. Those are **different origins**, so it's a **cross-origin request**. The browser sends a **preflight `OPTIONS` request** first; S3 answers with the CORS headers **only if the requesting origin matches `AllowedOrigins`**. If it doesn't match, the browser **blocks the request** — even though the bytes could reach S3.

So the URL in the policy = *"I trust pages served from this exact origin to talk to this bucket."* In this repo `cors_allowed_origins` defaults to `[]`, and the CORS rule is created only when the list is non-empty — so the real deployment passes the ALB DNS name (and `http://localhost:3000` for local dev).

💡 **Pro tip:** `AllowedOrigins` must match **exactly** — `https://app.com` and `https://www.app.com` are different origins. Wildcards (`*`) work but are discouraged with credentials.

**Q: What is the difference between CORS and a bucket policy?**
**A:** CORS is a **browser rule** enforced *by the browser* (client side) — it controls whether JS running on a page may read the response. A bucket policy is an **AWS/IAM rule** enforced *by S3* — it controls whether a request is authorized at all. You need the bucket policy/IAM to *allow* the action **and** CORS to let the browser *use* the response. They solve different problems.

**Q: What is S3 Glacier?**
⭐ Direct question the user asked.
**A:** Glacier is S3's **long-term archival storage family** — much cheaper per GB, but retrieval is slower and often costs extra. It's for data you keep for compliance/backup and rarely read.
| Class | Retrieval time | Use case |
| :--- | :--- | :--- |
| S3 Standard | Instant | Live data (our images) |
| S3 Standard-IA | Instant | Infrequent but needs instant access |
| S3 One Zone-IA | Instant | Non-critical, single AZ |
| **Glacier Instant Retrieval** | Milliseconds | Archives that are occasionally read |
| **Glacier Flexible Retrieval** | Minutes to hours | Backups, DR |
| **Glacier Deep Archive** | ~12 hours | 7–10 year compliance archives |

You normally reach Glacier via a **lifecycle rule** (e.g. "after 90 days move to Glacier"), not by choosing it at upload.

**Q: What lifecycle rules does this repo have?**
**A:**
- Images bucket: **abort incomplete multipart uploads after 3 days** — otherwise orphaned parts keep costing you money invisibly. ⭐ Common real-world cost leak.
- State bucket: expire **noncurrent versions after 90 days** + abort incomplete multipart uploads after 9 days.

**Q: Why is public access blocked if the browser uploads/downloads directly?**
**A:** Because the browser uses **presigned URLs**, which are cryptographically signed and time-limited. The bucket stays 100% private; access is granted per-object, per-request, per-expiry. This is far safer than making objects public.

**Q: How does a presigned URL work?**
**A:** The backend (holding IAM permissions) calls the S3 SDK `getSignedUrl`, which signs the request with its credentials and an expiry. The returned URL contains the signature. Anyone holding it can perform **that one action on that one key** until it expires. No AWS credentials are exposed to the browser. ⭐ This is why the backend never proxies image bytes.

**Q: Why store `uploads/` and `processed/` in the same bucket?**
**A:** Simpler permissions and lifecycle rules, plus the Lambda reads and writes in one place. Prefixes act like folders. Trade-off: you must be careful that the Lambda trigger only fires on `uploads/` (`filter_prefix = "uploads/"`) so it doesn't reprocess its own output.

**Q: What encryption does the images bucket use?**
**A:** **SSE-S3 with AES256** by default (`apply_server_side_encryption_by_default`). Every object is encrypted at rest automatically. Bucket is also private and only reachable over HTTPS (see next question).

**Q: What does the bucket policy in `modules/s3` actually enforce?**
⭐ Read it: it's a `DenyInsecureTransport` statement — **deny all `s3:*` if `aws:SecureTransport = false`**. Meaning: HTTP requests are rejected; only HTTPS is allowed. This is a security best practice ("encryption in transit").

**Q: Why does the bucket policy have `depends_on` the public access block?**
**A:** Ordering. If you attach a bucket policy before/without the public access block, S3 may treat the bucket as public and reject the policy with **"Access Denied: because public policies are blocked"**. Terraform needs the public access block to exist first.

**Q: What is a presigned URL's maximum expiry?**
**A:** Up to **7 days** (when signed with SigV4 and long-lived credentials). Shorter is safer — the backend typically uses ~1 hour. For temporary IAM credentials, the URL cannot outlive the credentials.

**Q: S3 consistency model?**
**A:** S3 is now **strongly consistent** for all reads (overwrites, deletes, list). Historically it was eventually consistent for overwrites — safe to say "modern S3 is strongly consistent".

**Q: What is request style — path-style vs virtual-hosted?**
**A:** Virtual-hosted: `https://bucket.s3.region.amazonaws.com/key`. Path-style: `https://s3.region.amazonaws.com/bucket/key`. Virtual-hosted is the default and needed for some TLS setups. Bucket names must not contain dots for HTTPS virtual-hosted style.

### S3 use cases (general)
Static websites, backups, data lakes, media storage, log archiving, big-data input, artifact/state storage, cross-region replication, Glacier archival.

---

## 3.4 ECR (Elastic Container Registry) 📦

### What it is
AWS's **private Docker image registry** — where your built container images live so ECS/Lambda can pull them.

### Core concepts
- **Repository** = one per image name (we have 3).
- **Image tag** = version label (`latest`, a git SHA).
- **Image URI** = `<account>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag>`.
- **Tag mutability**: `MUTABLE` (a tag can be overwritten, e.g. `latest`) vs `IMMUTABLE` (a tag cannot be reused — safer, auditable).
- **Scan on push** = automatic vulnerability scan of the image when pushed.
- **Lifecycle policy** = auto-delete old/untagged images to control cost.

### Q&A
**Q: How many ECR repos and why three?**
**A:** Three: `image-service/backend`, `image-service/frontend`, `image-processor/lambda`. Each deployable artifact has its own versioned lifecycle and CI pipeline, so it gets its own repo.

**Q: What does `image_tag_mutability` mean and what does this repo use?**
**A:** `MUTABLE` (set in `envs/dev/main.tf`) means the same tag — including `latest` — can be overwritten with a new push. `IMMUTABLE` forbids overwriting a tag, which is safer for auditability. ⭐ Improvement to mention: use `IMMUTABLE` and deploy by **git SHA**, leaving `latest` only as a convenience. CI already pushes both `${GITHUB_SHA}` and `latest`.

**Q: What is the lifecycle policy doing?**
**A:** It keeps only the **last 3 images** per repo and expires untagged ones. Without it the registry grows forever (you pay per GB-month) even though old layers are useless. ⭐ Cost hygiene.

**Q: What is "scan on push" and does it replace other security?**
**A:** It runs the basic **basic scan** (CVE detection in OS packages) whenever an image is pushed. It's a first line, not a replacement for ongoing scanning (ECR enhanced scanning/Inspector) or image hardening.

**Q: How does ECS get the image?**
**A:** The **task execution role** (with `AmazonECSTaskExecutionRolePolicy`) calls ECR to pull the layers. That's why the execution role needs `ecr:GetDownloadUrlForLayer`, `BatchGetImage`, etc.

**Q: How does Lambda use ECR?**
**A:** The Lambda is a **container-image Lambda** (`package_type = "Image"`). Lambda pulls from ECR at deploy/runtime using the Lambda service role. We `ignore_changes = [image_uri]` in Terraform because the CI pipeline updates the image after Terraform created the function.

**Q: ECR vs Docker Hub / S3?**
**A:** ECR is private by default, integrates natively with ECS/Lambda and IAM, supports image scanning and lifecycle policies. Docker Hub is public/shared and rate-limited. S3 stores *any* bytes but ECS/Lambda can't pull runnable images from it directly.

### Use cases of ECR
Store CI artifacts, immutable deploy versions, vulnerability scanning in the pipeline, cross-account/cross-region replication, Lambda container images.

---

## 3.5 RDS (Relational Database Service) 🐘

### What it is
A **managed relational database** — AWS runs the server, patching, backups and failover; you manage the data and schema. This repo uses **PostgreSQL 16**.

### Core concepts
- **Engine** = MySQL/PostgreSQL/MariaDB/SQL Server/Oracle/Aurora.
- **Instance class** = size (`db.t4g.micro` = tiny, ARM-based, cheap).
- **Storage** = EBS volume; **gp3** = current general-purpose SSD. **Autoscaling** can grow it.
- **Multi-AZ** = a standby copy in another AZ with automatic failover (**reliability**, not read scaling).
- **Read replica** = a read-only copy (**scaling reads**, not failover).
- **Subnet group** = which subnets the DB can live in (needs ≥2 AZs, ours validates that).
- **Parameter group** = engine settings.
- **Backup retention** = automated daily backups + **point-in-time recovery (PITR)** for the retention window.
- **Snapshot** = point-in-time copy; final snapshot on delete if configured.
- **Deletion protection** = API-level guard against accidental deletion.
- **`manage_master_user_password`** = AWS generates, stores and rotates the master password in Secrets Manager.
- **`publicly_accessible = false`** = not reachable from the internet.

### Q&A
**Q: Walk me through the RDS setup.**
**A:** PostgreSQL 16 on `db.t4g.micro`, `gp3` storage, 10 GB with autoscaling to 20 GB, **encrypted at rest**, in the **private subnets** via a DB subnet group, `publicly_accessible = false`, single-AZ in dev (Multi-AZ in prod), 7-day automated backups, auto minor upgrades, deletion protection off in dev, and the master password **managed by Secrets Manager** (`manage_master_user_password = true`). Access is locked to the ECS security group on port 5432.

**Q: Why PostgreSQL and not DynamoDB?**
**A:** The data is **relational** — users, images, statuses, timestamps — with joins and structured queries, which fits SQL and Prisma naturally. DynamoDB would demand careful key design and no joins. Trade-off: RDS needs management and its own subnet/backups; DynamoDB scales serverlessly but your access patterns must be fixed upfront.

**Q: Multi-AZ vs Read Replica?**
⭐ Very common. Multi-AZ = **high availability/failover** (standby, not readable). Read Replica = **read scaling** (readable copy, asynchronous). Our dev uses neither (cost); prod would use Multi-AZ at minimum.

**Q: How is the DB password handled? Why is that important?**
**A:** `manage_master_user_password = true` makes AWS create the secret in Secrets Manager and rotate it. The app receives it via the ECS **`secrets` block** (`"${master_secret_arn}:password::"`), injected at container start — never in Git, never in plain env vars, never in Terraform. ⭐ This is the "zero static keys" principle applied to the database.

**Q: Why must a DB subnet group have at least 2 subnets?**
**A:** AWS requires subnets in at least two AZs so the DB can support Multi-AZ and be placed resiliently. Our module validates `length(subnet_ids) >= 2` and fails fast with a clear message.

**Q: Why is RDS in a private subnet?**
**A:** A database must never be internet-reachable. It's reachable only from the ECS security group over 5432, so the only path in is through the application.

**Q: What happens to data on `terraform destroy`?**
**A:** In dev, `skip_final_snapshot = true` and `deletion_protection = false` → the DB is deleted with **no final snapshot**. In prod we'd set `skip_final_snapshot = false`, `deletion_protection = true`, Multi-AZ on. ⭐ Explain the risk consciously — it shows maturity.

**Q: How is storage encryption done and can it be changed later?**
**A:** `storage_encrypted = true` at creation, using AWS-managed KMS keys. ⭐ Encryption **cannot be turned on for an existing unencrypted instance** — you must snapshot → copy with encryption → restore. Hence enable it from day one.

### Use cases of RDS
Transactional apps, user/account data, e-commerce, reporting with joins, anything needing ACID (Atomicity, Consistency, Isolation, Durability) transactions. Prisma (this project's ORM) talks to it.

---

## 3.6 ECS on Fargate 🐳

### What it is
**Elastic Container Service** = AWS's container orchestrator (like a managed Kubernetes-lite). **Fargate** = the serverless launch type: you give it a container spec, AWS runs it — **no EC2 instances to patch**.

### Core concepts
- **Cluster** = logical group of services/tasks (`image-service-dev-cluster`).
- **Task Definition** = the **blueprint**: image, CPU, memory, ports, env vars, secrets, roles, logging. Think "recipe".
- **Task** = a **running instance** of a task definition (a running container).
- **Service** = keeps N tasks running and registers them with the ALB (self-healing + rolling deploys).
- **Launch type** = Fargate (serverless) or EC2 (you manage nodes).
- **Network mode `awsvpc`** = each task gets its **own ENI and private IP** (required for Fargate; lets target groups use `target_type = ip`).
- **Desired count** = how many tasks should run.
- **Circuit breaker with rollback** = if a deployment keeps failing health checks, abort and roll back to the last good version.
- **Task role vs Execution role** = app permissions vs platform permissions (see IAM).

### Q&A
**Q: Explain ECS Fargate in this project.**
**A:** One cluster `image-service-dev-cluster`. Two services: backend (port 3001, 0.5 vCPU / 1 GB) and frontend (port 3000). Both use `awsvpc` mode, run in the private subnets, register into their own ALB target group, and log to `/ecs/<prefix>/<service>` in CloudWatch. Each has its own **task role**; a shared **execution role** pulls images and injects secrets. Deployment uses the **circuit breaker with rollback**.

**Q: Why Fargate over EC2 launch type?**
**A:** No servers to patch, no capacity planning, pay per task-second, native ALB integration. Trade-off: more expensive per vCPU-hour at large scale — EC2 launch type wins if you run hundreds of containers.

**Q: Why Fargate for the API but Lambda for image processing?**
⭐ Both compute models used on purpose:
- API/WebSocket = **long-running, stateful connections** → always-on containers fit.
- Image processing = **short, bursty, CPU-heavy** → Lambda pays per use and scales automatically.

**Q: What is `assign_public_ip = false` and why?**
**A:** Tasks get only private IPs; outbound traffic goes through the NAT gateway. This keeps them unreachable from the internet. For a Fargate task in a public subnet with `assign_public_ip = false` you'd have no egress — but ours are in private subnets with NAT, so egress works.

**Q: How do ECS tasks get environment variables and secrets?**
**A:** Plain config via `environment` (NODE_ENV, DB_HOST, S3_BUCKET, AWS_REGION …). Sensitive values via `secrets`, which reference Secrets Manager ARN + JSON key, e.g. `DB_PASSWORD = "${master_secret_arn}:password::"` and `JWT_SECRET = "${app_secret_arn}:jwt_secret::"`. The **execution role** needs `secretsmanager:GetSecretValue` (given by the `read-secrets` inline policy).

**Q: Why `health_check_grace_period_seconds = 60`?**
**A:** Gives the container time to start before the ALB starts failing it. Without it a slow-booting app gets killed in a restart loop.

**Q: How are log groups created and why set retention?**
**A:** One CloudWatch log group per service at `/ecs/<prefix>/<service>`, retention **14 days**, configured with `for_each` over services. Retention matters because CloudWatch Logs charges for stored data — never set "never expire" in a learning account.

**Q: How does CI deploy to ECS?**
**A:** The workflow registers a new task definition / updates the service and calls `ecs:UpdateService` (a force deployment). The GitHub OIDC role has exactly `ecs:RegisterTaskDefinition`, `ecs:DescribeTaskDefinition`, `ecs:UpdateService`, `ecs:DescribeServices`, plus `iam:PassRole` constrained with `iam:PassedToService = ecs-tasks.amazonaws.com`.

**Q: What is Fargate Spot?**
**A:** Cheaper Fargate capacity that can be reclaimed with a 2-minute warning — good for interruption-tolerant background work. Mention as a cost option; not used here.

### Use cases of ECS/Fargate
Microservices, APIs, web apps, batch jobs, WebSocket servers, anything containerised that must run continuously; Fargate when you want no ops.

---

## 3.7 ALB (Application Load Balancer) ⚖️

### What it is
A **Layer 7 (HTTP/HTTPS) load balancer** that spreads incoming requests across multiple targets and routes them by rules (path, host, header).

### Core concepts
- **Listener** = port + protocol that listens (here HTTP:80).
- **Rule** = condition → action (e.g. `/images/*` → backend target group).
- **Priority** = rule evaluation order (lower number wins).
- **Default action** = catch-all (`/*` → frontend).
- **Target group** = set of targets + health check config.
- **Health check** = periodically calls a path; unhealthy targets are removed.
- **Stickiness** = cookie-based pinning of a client to one target (needed for WebSocket).
- **ALB vs NLB** = Layer 7 HTTP (paths, WebSocket) vs Layer 4 TCP (raw speed, static IPs).
- **Target types** = `instance` (EC2), `ip` (Fargate/on-prem), `lambda`.

### Q&A
**Q: Why ALB instead of API Gateway?**
**A:** It's cheaper for container backends, routes directly to ECS target groups (no VPC Link), and supports **WebSocket upgrade natively** — essential for Socket.IO. API Gateway would suit a 100% serverless (Lambda-only) API or when you want built-in authorizers/throttling.

**Q: How does routing work here?**
**A:**
```
/auth/*       → backend  (priority 10)
/images/*     → backend
/internal/*   → backend
/health       → backend
/socket.io/*  → backend
default /*    → frontend
```
One DNS name for both apps; the browser never sees ports.

**Q: Why enable stickiness only on the backend target group?**
**A:** Socket.IO keeps connection state in memory. Without stickiness a refresh could land on a different task and lose the socket. Sticky cookie (`AWSALB`) pins the user to one task for a day. The frontend is stateless, so no stickiness needed. ⭐ Alternative: share state in Redis (ElastiCache) and remove stickiness — the more scalable pattern, costlier here.

**Q: Health checks — how configured?**
**A:** Backend `GET /health`, frontend `GET /`, HTTP, HTTP codes 200–399 for target groups (`matcher`). 2 successes = healthy, 2–3 failures = unhealthy. ECS service gets a 60s grace period.

**Q: ALB vs NLB vs CloudFront?**
| | ALB | NLB | CloudFront |
| :--- | :--- | :--- | :--- |
| Layer | 7 (HTTP) | 4 (TCP/UDP) | CDN / edge |
| Routing | path/host/header | port/protocol | cache + origin |
| WebSocket | Yes | Yes (TCP) | Limited |
| Use | Web apps | gaming/IoT/static IP | global static content |

**Q: What is `drop_invalid_header_fields = true`?**
**A:** ALB drops requests with malformed/ambiguous headers — a hardening measure against header-smuggling attacks.

**Q: Is HTTPS configured?**
**A:** Not yet — dev only has HTTP:80. For prod: request an **ACM (AWS Certificate Manager)** certificate, add a **443 listener**, and redirect 80→443. ⚠️ **Be ready for this question** — flag it yourself and show you know the gap.

**Q: How does the ALB know ECS task IPs?**
**A:** The ECS service registers task ENIs into the target group automatically (target type `ip`). When a task restarts it deregisters/re-registers; `deregistration_delay` (default 300s) controls how long it drains old connections.

**Q: What is an LCU?**
**A:** **Load Balancer Capacity Unit** — the ALB pricing metric based on new connections, active connections, processed bytes, and rule evaluations. Talk about it when discussing cost.

### Use cases of ALB
Microservice routing, blue/green & canary deploys, WebSocket apps, path/host-based APIs, TLS termination, health-checked autoscaling fleets.

---

## 3.8 Lambda (image processor) ⚡

### What it is
**Serverless functions** — you upload code (or a container image), AWS runs it on demand, scales automatically, and bills per invocation + duration.

### Core concepts
- **Function** = your code + config (runtime, memory, timeout, role).
- **Invocation** = one execution triggered by an event.
- **Trigger / event source** = what calls it (S3, API Gateway, SQS, EventBridge, schedule).
- **Event source mapping** = the poller-based integration (for SQS/Kinesis/DynamoDB streams).
- **Concurrency** = how many run at once; account default 1000 (can be raised).
- **Cold start** = delay when a new execution environment is created; warm invocations are fast.
- **Timeout** = max run time (max 15 minutes).
- **Memory** = 128 MB–10 GB; ⭐ **CPU scales with memory**.
- **Container image vs .zip** = image supports up to 10 GB and any runtime; zip is smaller/faster to start.
- **DLQ / retries** = failed async invocations retry twice, then go to a dead-letter queue if configured.
- **Execution role** = IAM permissions for the function.

### Q&A
**Q: Walk me through the Lambda design.**
**A:** A **container-image** Lambda (`image-processor`) built from `nodejs:20` + **Sharp**, default 1024 MB / 60 s, with an **execution role** that can `s3:GetObject` and `s3:PutObject` on the images bucket plus `secretsmanager:GetSecretValue`. It is triggered by an **S3 event notification** on `uploads/` (`s3:ObjectCreated:*`). It downloads the original, compresses with Sharp (`resize` to max width, `jpeg` at quality 80, respecting EXIF rotation), writes to `processed/`, then notifies the backend over HTTP with an `x-api-key` shared secret.

**Q: Why Lambda and not a background worker in ECS?**
**A:** Image compression is CPU/memory heavy. Doing it in the API container would starve user requests. Lambda isolates the workload, scales to many concurrent invocations, and costs nothing when idle.

**Q: How is the S3 trigger wired in Terraform?**
**A:** Two things must exist:
1. `aws_lambda_permission` — resource-based policy letting **S3** invoke the function (`principal = s3.amazonaws.com`, `source_arn = bucket ARN`).
2. `aws_s3_bucket_notification` — the event config, filtered to `uploads/`.
⭐ **Order matters** — the notification has `depends_on = [aws_lambda_permission.s3]`, otherwise S3 rejects it ("Unable to validate the following destination configurations").

**Q: Why is the Lambda NOT in the VPC?**
**A:** It only talks to S3 and the public ALB. Outside the VPC it has internet access by default, so no NAT cost. ⚠️ **But** that means the callback to the backend goes over the **public internet on plain HTTP** — the shared secret is unencrypted. Improvement: put Lambda in the VPC and use an **internal ALB** or an **SQS queue**, or expose the callback over HTTPS. Be ready to say this — it's a genuine security gap.

**Q: How does it handle failures?**
**A:** If **processing** fails (corrupt image), it reports `type: 'failed'` and does **not** rethrow — so S3 doesn't retry and duplicate the failure notification. If **reporting** fails (backend unreachable), it **rethrows** so S3 retries the whole event (up to 2 retries). It also retries the callback once internally. A corrupt image marks the record `FAILED` instead of hammering S3 retries.

**Q: What is the `ignore_changes = [image_uri]` for?**
**A:** CI/CD pushes a new image and calls `update-function-code`. If Terraform also tracked `image_uri` it would try to reset the function to the old image on the next apply — a fight between two tools. So Terraform ignores that field; **CI owns the image, Terraform owns the infrastructure.** Initial `image_uri` uses `${ecr_lambda}:latest` as a bootstrap placeholder.

**Q: How could the notification path be improved?**
⭐ Design question. The Lambda supports `NOTIFY_MODE=api` or `sqs`. In SQS mode it would `SendMessage` to a queue and the backend would consume it — decoupled, buffered, survives backend downtime, no public HTTP callback. The `modules/sqs` folder is the start of that but is currently a stub.

**Q: Cold starts — how would you reduce them?**
**A:** Provisioned Concurrency (pre-warmed), smaller image / fewer dependencies, ARM64 (Graviton, cheaper and often faster), keeping the function warm, or choosing memory wisely. Note Sharp compiles native binaries, so keep the image lean.

**Q: How do you test it locally?**
**A:** The repo has `test/local.test.js` and the handler is a plain async function; you can invoke it with a fake S3 event object. Container image Lambdas can also be run with the AWS Lambda Runtime Interface Emulator (RIE).

### Use cases of Lambda
Event-driven processing, S3 pipelines, cron jobs, API backends, glue code, image/PDF/video processing, stream processing.

---

## 3.9 CloudWatch 📊

### What it is
AWS's **monitoring and logging** service — metrics, logs, dashboards, alarms.

### Concepts & Q&A
- **Log group** = container for logs from one source (`/ecs/<prefix>/<service>`, `/aws/lambda/<fn>`).
- **Log stream** = logs from one instance/task.
- **Retention** = how long logs are kept (we set **14 days**).
- **Metric** = numeric time series (CPUUtilization, Invocations, Errors, Duration).
- **Alarm** = a rule on a metric that triggers an action (SNS email, autoscaling).
- **Logs Insights** = a query language for searching logs.

**Q: What monitoring exists today, and what's missing?**
**A:** We have **centralised logs** for ECS and Lambda with retention. Missing (good improvements to mention): CloudWatch **alarms** (5xx rate, Lambda errors, RDS connections, CPU > 80%), **dashboards**, **X-Ray distributed tracing**, and **VPC Flow Logs**.

**Q: How would you debug "images aren't processing"?**
**A:** Start at the Lambda log group — did it invoke? If yes, read the error (Sharp failure? S3 access denied?). If no, check the S3 event notification exists and the Lambda permission is in place, and that the key starts with `uploads/`. Then check the backend callback logs and the DB status. ⭐ This is a structured debugging answer.

### Use cases
Debugging, performance tuning, alerting/on-call, cost/usage analysis, compliance log retention.

---

## 3.10 Secrets Manager 🔐

### What it is
A managed store for **secrets** (passwords, API keys, tokens) with **automatic rotation**, fine-grained IAM, and encryption via KMS.

### Q&A
**Q: Secrets Manager vs SSM Parameter Store?**
| | Secrets Manager | SSM Parameter Store |
| :--- | :--- | :--- |
| Cost | ~$0.40/secret/month | Standard params free |
| Rotation | Built-in (e.g. RDS auto-rotate) | Manual / custom Lambda |
| Best for | Passwords, API keys, DB creds | Config, non-secret params, cheap secrets |

⭐ **Why we use it:** it's the only one that **natively rotates RDS passwords** and integrates with the ECS `secrets` block.

**Q: What secrets does this repo have?**
**A:**
1. **RDS master password** — auto-created by `manage_master_user_password`.
2. `<prefix>/callback-secret` (`aws_secretsmanager_secret.callback`) — the shared secret for the Lambda → backend `/internal` call.
3. `<prefix>/app` (`aws_secretsmanager_secret.app`) — holds `jwt_secret` (the JSON key referenced by ECS).

⚠️ **How the values are populated:** `random_password` + `aws_secretsmanager_secret_version` create the `jwt_secret` JSON and the callback secret. Caveat: generated values live in Terraform state in plaintext. For production rotation, prefer a CI step or Secrets Manager rotation Lambda instead.

**Q: Why not just use environment variables?**
**A:** Env vars are visible in the console/task definition and can leak in logs. Secrets Manager keeps values out of the task definition, rotates them, and audits access.

**Q: What is `recovery_window_in_days`?**
**A:** How long a deleted secret can be recovered (0 = immediate, forced delete — used in dev with `allow_force_destroy`; 7 days in prod).

### Use cases
DB credentials, API keys, third-party tokens, rotation compliance, cross-service secret sharing.

---

## 3.11 SQS / SNS / EventBridge (planned & general talk) 📨

Even though SQS is a stub here, interviewers ask about it when they see `NOTIFY_MODE=sqs`.

- **SQS (Simple Queue Service)** = managed message **queue**, pull-based. Decouples producer and consumer. **Standard** (at-least-once, best-effort order, high throughput) vs **FIFO** (exactly-once processing, strict order, lower throughput). Has a **DLQ (dead-letter queue)** for repeatedly failing messages, **visibility timeout** (how long a consumer hides a message), and **long polling** (wait for messages instead of hammering).
- **SNS** = pub/sub **topics**, push-based, fan-out to many subscribers.
- **EventBridge** = event bus with rules and routing (superset of old CloudWatch Events).

**Q: Why would you move the Lambda→backend notification to SQS?**
**A:** Today it's a synchronous HTTP callback; if the backend is down, the notification is lost/retried over the public internet. With SQS the Lambda just enqueues and returns; the backend consumes at its own pace, messages are durable, retries are built in, and a DLQ captures poison messages. Trade-off: added latency and one more resource (+ the backend needs a consumer, which its `sqs-event-consumer.service.ts` is prepared for).

**Q: SQS vs SNS vs EventBridge in one line?**
**A:** SQS = one consumer pulls; SNS = push to many; EventBridge = rule-based routing between AWS services.

### Use cases
Async workflows, decoupling, load levelling (spiky traffic), fan-out notifications, retries/DLQ, event-driven architectures.

---

## 3.12 Services you'll be asked about but don't (yet) use 🧭

Be ready to say *what they are, why not, and when you would*.

| Service | What it is | Why not here | When you'd add it |
| :--- | :--- | :--- | :--- |
| **Route 53** | Managed DNS | Using the raw ALB DNS name | Custom domain (`api.example.com`) |
| **ACM** | Free TLS certificates | Dev uses HTTP | HTTPS on the ALB (prod, mandatory) |
| **CloudFront** | CDN + edge cache | Low traffic, single region | Global users, cache processed images |
| **ElastiCache (Redis)** | Managed in-memory cache / shared state | Cost; stickiness works fine | Scaling WebSocket across tasks, sessions |
| **API Gateway** | Managed API front door | ALB cheaper for containers | Fully serverless APIs, throttling, API keys |
| **DynamoDB** | Serverless NoSQL key-value | Relational data + Prisma | Massive-scale single-table access |
| **Aurora** | Cloud-native MySQL/Postgres | Cost | High availability + read scaling |
| **WAF** | Web Application Firewall (Layer 7) | Dev scope | Protect the ALB from bot/SQLi/XSS attacks |
| **KMS** | Managed encryption keys | SSE-S3 is enough | Customer-managed keys, compliance, audit |
| **SSM Session Manager** | Shell into instances without SSH | No EC2 | Bastion-free instance access |
| **X-Ray** | Distributed tracing | Not yet | Latency debugging across services |
| **Backup** | Central backup service | RDS backups suffice | Cross-service backup policy |
| **GuardDuty / Security Hub** | Threat detection & posture | Dev scope | Production security monitoring |
| **VPC Flow Logs** | Network traffic logs | Cost/scope | Security investigations |
| **AWS Config** | Resource compliance history | Dev scope | Drift/compliance auditing |

💡 **Pro tip:** When they ask "what's missing?", never just say "nothing". Name one security gap and one observability gap — it signals senior awareness.

---

# PART 4 — CI/CD & GitHub OIDC 🚀

### Q1. What is OIDC and why is it the headline of this project?
**A:** **OpenID Connect** is an identity layer on OAuth2. GitHub Actions can present a **short-lived signed token** proving *which repo/branch/environment* the workflow belongs to. AWS is configured to **trust GitHub as an OIDC provider** and exchange that token for temporary AWS credentials via `sts:AssumeRoleWithWebIdentity`. Result: **no long-lived AWS access keys** stored in GitHub Secrets. Nothing to leak or rotate.

### Q2. Walk me through the OIDC setup in Terraform.
**A:**
1. `aws_iam_openid_connect_provider` with `url = https://token.actions.githubusercontent.com`, `client_id_list = ["sts.amazonaws.com"]`, a thumbprint list.
2. For each role, a **trust policy** allowing `sts:AssumeRoleWithWebIdentity` with two conditions:
   - `aud == sts.amazonaws.com`
   - `sub` matches a specific repo **and** context (`repo:owner/repo:pull_request`, `...:ref:refs/heads/main`, `...:environment:dev`).
3. Five roles: `infra-plan` (ReadOnly + state lock), `infra-apply` (Admin), `backend`, `frontend`, `lambda` (scoped ECR/ECS/Lambda permissions).

### Q3. Why is the `sub` condition so important?
⭐ Security-critical.
**A:** Without a repo/branch condition, **any** GitHub repository in the world could assume your role. Locking `sub` to `repo:owner/repo:ref:refs/heads/main` (or `:environment:dev` for manual-gated applies) means only the intended repo/branch can get in. This is the #1 OIDC mistake and a favourite interview question.

### Q4. Why does the workflow need `permissions: id-token: write`?
**A:** That permission lets the workflow request the OIDC token from GitHub. Without it, `configure-aws-credentials` fails. `contents: read` is needed for checkout.

### Q5. What does the `aws-actions/configure-aws-credentials` step do?
**A:** It requests the OIDC token, calls STS `AssumeRoleWithWebIdentity` with `role-to-assume`, and exports temporary credentials as environment variables for the rest of the job.

### Q6. What's the dev vs prod CI flow you described?
**A:** Pull Requests → `fmt`, `validate`, `tflint`, `plan`, and the plan is posted back as a PR comment (using the read-only role). Merge to main → `apply` with a **GitHub Environment approval gate** (using the apply role) so a human approves production changes. ⭐ Environment protection + OIDC is the zero-key equivalent of "key rotation + approval".

### Q7. Are there any issues in the current workflows?
⭐ Honest answers here impress.
**A:** Yes, a few things to fix:
- The backend/lambda workflows reference `${{secrects.AWS_REGION}}` — a **typo** (`secrects` → `secrets`), so the region would be empty.
- The `ROLE_ARN` values must be stored as GitHub **secrets** (they weren't shown).
- The lambda workflow's `update-function-code` steps are **commented out**, so pushing an image doesn't yet update the function.
- Setting `LAMBDA_API_KEY` through workflow env vars partially contradicts "zero static keys" — it should come from Secrets Manager.
- `AWS_REGION` should simply be a workflow `env:`, not a secret.

### Q8. How do you stop two applies running at once?
**A:** S3 state locking (`use_lockfile = true`) stops Terraform-level conflicts, and a GitHub Actions **concurrency group** (`concurrency: terraform-dev`) queues/cancels duplicate workflow runs at the CI level. Use both.

### Q9. What would you add to make CI/CD production-grade?
**A:** `checkov`/`trivy` IaC security scanning, `tflint`, a `terraform fmt -check`, plan output in the PR, environment approvals, concurrency groups, pinned action versions by SHA, and a separate apply for each env.

---

# PART 5 — Scenario, "what if" and troubleshooting questions 🧯

**Q: An image upload never triggers Lambda. How do you debug?**
**A:** 1) Is the object under `uploads/`? (`filter_prefix` blocks anything else.) 2) Does `aws_s3_bucket_notification` exist and is it `Enabled`? 3) Does `aws_lambda_permission` grant S3 `lambda:InvokeFunction` with the right `source_arn`? 4) Check CloudWatch Logs for the function — zero log streams means it was never invoked. 5) Check IAM on the bucket/function.

**Q: The Lambda runs but the browser never shows "processed". How do you debug?**
**A:** Check the Lambda logs for the backend callback result. 401/403 → wrong `x-api-key`. Connection error → ALB/backend URL or SG problem. Then check backend logs, then RDS (`status` column), then the WebSocket connection (stickiness/JWT in the handshake).

**Q: The backend can't connect to RDS. Why?**
**A:**
- No ingress rule on 5432 from the ECS SG (⚠️ remember it lives in `compute.tf`, not the rds module).
- Wrong `DB_HOST`/port/name.
- Secret value not populated (JWT/DB credentials).
- Task in a subnet without a route to RDS, or the DB subnet group isn't in the same VPC.

**Q: ECS task is stuck in "pending"/keeps restarting. Why?**
**A:** Image pull fails (bad ECR URL / missing execution role perms), the app crashes on start (missing required env/secret), the container port doesn't match the target group, health check path is wrong, or the task can't reach Secrets Manager/ECR (no NAT/endpoint egress).

**Q: The ALB returns 502/503. Why?**
**A:** 502 → target responded with garbage or connection refused (wrong container port, app not listening on 0.0.0.0). 503 → no healthy targets (health check failing, tasks not registered, wrong path/port). Always check target group health in the console and `TargetResponseTime`/`UnhealthyHostCount` metrics first.

**Q: `terraform apply` says the S3 bucket name already exists. Why?**
**A:** Bucket names are **globally unique**. Another account (or an earlier run) owns it. Hence the account ID in the name — but empirically you may still need a random suffix.

**Q: Two engineers run `apply` at the same time — what happens?**
**A:** The second waits on/errors out due to **state locking** (`use_lockfile = true`). With a stale lock you can force-unlock with `terraform force-unlock <ID>` after confirming nobody is applying.

**Q: Someone changed something in the console. What now?**
**A:** `terraform plan` shows **drift**. Decide: adopt the change into code, or let Terraform revert it. Best practice is to prevent console changes entirely and use `terraform import` to bring in anything that must stay.

**Q: Costs are unexpectedly high. What would you check?**
**A:** NAT Gateway hours + data, idle RDS instances and storage, ALB LCU hours, CloudWatch Logs stored with no retention, ECR untagged images, S3 incomplete multipart uploads, data transfer across AZs/regions. Then set budgets and alarms. (The images bucket already handles multipart cleanup via lifecycle.)

**Q: How would you make this production-ready?**
**A:** HTTPS (ACM + 443 + redirect) and a custom domain (Route 53); Multi-AZ RDS + deletion protection + final snapshots; `single_nat_gateway = false`; ECS autoscaling + 2+ tasks; CloudWatch alarms + SNS; X-Ray; WAF; `IMMUTABLE` ECR tags deployed by SHA; remove the public HTTP callback in favour of private networking/SQS; interface VPC endpoints for ECR/Secrets/Logs; backup and disaster-recovery plan; secrets fully populated and rotated; least-privilege apply role.

**Q: How do you prove the infra is reproducible?**
**A:** `terraform destroy` then `terraform apply` in a scratch account, or spin up `envs/prod` from the same modules. This "rebuild test" is literally Step 10 in the roadmap.

**Q: What would break if `eu-north-1` had an outage?**
**A:** Everything, since it's a single region. Recovery = restore from RDS snapshots, redeploy containers (images live in ECR in the same region), recreate infrastructure with Terraform. For real resilience: multi-region, cross-region replicated S3, and Route 53 failover.

---

# PART 6 — Rapid-fire one-liners + glossary ⚡

## 6.1 Rapid-fire

- **IaC?** Managing infrastructure through version-controlled code.
- **State?** Terraform's record of what it created.
- **Provider?** Plugin that talks to an API (here, the AWS provider).
- **Module?** A reusable folder of Terraform config.
- **`for_each` vs `count`?** Map/set with stable keys vs index-based.
- **`depends_on`?** Explicit ordering hint.
- **`lifecycle`?** Rules for create/destroy behaviour.
- **Drift?** Real infra differs from code.
- **Blast radius?** How much breaks when something fails.
- **Least privilege?** Only the permissions actually needed.
- **Presigned URL?** Temporary signed link to one S3 action.
- **CORS?** Browser rule letting one origin read another's response.
- **Glacier?** Cheap, slow archival storage.
- **AZ?** Isolated data centre within a region.
- **NAT vs IGW?** One-way out vs two-way door.
- **SG vs NACL?** Stateful, resource-level vs stateless, subnet-level.
- **Multi-AZ vs Read Replica?** Failover vs read scaling.
- **Task vs Execution role?** App code vs ECS platform.
- **Cold start?** Delay creating a new Lambda environment.
- **OIDC?** Keyless identity federation for CI/CD.
- **Sticky session?** Pinning a user to one backend task.
- **LCU?** ALB's usage-based billing unit.
- **DLQ?** Queue for messages that keep failing.

## 6.2 Glossary (plain meanings)

| Term | Meaning |
| :--- | :--- |
| IaC | Infrastructure as Code — infra defined in files |
| CIDR | IP range notation like `10.0.0.0/16` |
| AZ | Availability Zone — separate data centre in a region |
| IGW | Internet Gateway — VPC↔internet door |
| NAT | Network Address Translation — outbound-only internet for private subnets |
| ENI | Elastic Network Interface — a virtual network card |
| SG / NACL | Security Group (stateful) / Network ACL (stateless) |
| SSE | Server-Side Encryption |
| KMS | Key Management Service |
| TTL | Time To Live — how long something lasts |
| ETag | Entity tag — hash identifying an S3 object version |
| SigV4 | AWS Signature Version 4 — request signing scheme |
| STS | Security Token Service — issues temporary credentials |
| OIDC | OpenID Connect — identity federation protocol |
| PITR | Point-In-Time Recovery |
| LCU | Load Balancer Capacity Unit |
| Grace period | Time allowed before health checks count |
| Blue/Green | Deploy two versions, switch traffic |
| Canary | Send a small % of traffic to the new version |
| Drift | Reality vs code mismatch |
| Least privilege | Minimum required permissions |
| Blast radius | Scope of impact of a failure |
| Thundering herd | Many clients hitting at once |

---

# PART 7 — Professional advice & improvements for THIS repo 🛠️

> Use these as your "what would you improve?" answer. Pick 2–3 and explain the *why*, not just the *what*.

### 7.1 Security hardening (highest priority)
1. **HTTPS everywhere.** Add an **ACM certificate** + **443 listener** on the ALB and redirect 80→443. Right now the login JWT and WebSocket traffic travel in plain HTTP.
2. **Fix the Lambda→backend callback.** It goes over the **public internet on HTTP**. Options: put the Lambda in the VPC and call an **internal ALB**, or move to **SQS**, or at minimum use HTTPS and rotate the API key.
3. **Secret rotation.** Secrets are now generated by `random_password` + `aws_secretsmanager_secret_version`; the next step is rotation (Secrets Manager rotation Lambda or a CI `put-secret-value`) and removing values from Terraform state. ⚠️ Storing a generated value in Terraform puts it in state.
4. **Narrow `infra-apply`.** `AdministratorAccess` is a portfolio shortcut; use a scoped policy + permissions boundary, and keep the human **approval environment gate**.
5. **Enable `IMMUTABLE` ECR tags** and deploy by **git SHA**. `MUTABLE` + `latest` makes rollbacks ambiguous.
6. **Add interface VPC endpoints** (`ecr.api`, `ecr.dkr`, `secretsmanager`, `logs`) so private tasks stop depending on NAT/internet.
7. **WAF** in front of the ALB, **GuardDuty**, and **VPC Flow Logs** for production.
8. **S3 hardening:** add **access logging**, consider **SSE-KMS** for auditability, and add **MFA delete** to the state bucket.
9. **Never deploy secrets via workflow env vars.** The Lambda now fetches the callback secret at runtime via `CALLBACK_SECRET_ARN`; keep it that way.
10. **Enable versioning on the images bucket** if accidental overwrite/delete protection matters (or document why it's off — cost).

### 7.2 Reliability & operations
1. **ECS autoscaling** (target 60–70% CPU) instead of a fixed `desired_count`, and run **2+ tasks** across AZs in prod.
2. **RDS:** Multi-AZ, `deletion_protection = true`, `skip_final_snapshot = false`, and **Performance Insights** in prod.
3. **CloudWatch alarms + SNS**: ALB 5xx, unhealthy hosts, Lambda errors/duration, ECS CPU/mem, RDS connections/free storage, plus **AWS Budgets** for cost alerts.
4. **Retention discipline:** 14-day logs is good; add explicit guidance for prod.
5. **Health/readiness checks:** add a deep `/health` that verifies DB connectivity, not just "process is up".
6. **DLQ for Lambda** async invocations, or move to SQS with a DLQ.
7. **Backup/DR plan:** document RTO/RPO (Recovery Time/Point Objective) and test restores.

### 7.3 Code / Terraform hygiene
- Rename the typo file **`secrects.tf` → `secrets.tf`** and the typo workflow vars `secrects` → `secrets`.
- **Don't commit `.terraform/` or `tfplan`** (they're in `bootstrap/` locally — confirm they're gitignored; `tfplan` already is).
- Add a **`versions.tf`** with `required_version` (present in `providers.tf`) and pin provider versions (done: `~> 6.0`).
- Add **`terraform fmt -check`**, **`tflint`**, **`checkov`**, and **`pre-commit`** hooks.
- **Document the modules** (READMEs) — the root `README.md` is currently empty. ⭐ A good README is the cheapest portfolio win.
- Consider **test coverage** with `terratest` or at least `terraform validate` in CI.
- The **`modules/sqs`** stub contains an invalid `variable "" {}` block — either finish it or remove it before anyone runs `validate` on that folder.

### 7.4 Cost discipline
- Single NAT in dev ✅; per-AZ NAT in prod.
- Set **CloudWatch Logs retention** everywhere (done: 14 days).
- **ECR lifecycle** to prune old images ✅.
- S3 **lifecycle** to abort incomplete multipart uploads ✅.
- Use **Fargate Spot** or **Graviton (ARM)** where possible; the Lambda supports `arm64` via a variable.
- Turn off dev outside working hours (or a scheduled scale-to-zero) to avoid 24/7 RDS/ALB charges.
- Create an **AWS Budget** with alerts.

### 7.5 Observability
- Add **X-Ray** tracing across ALB → ECS → RDS and Lambda → S3 → backend.
- Add **custom metrics** (image processing duration, callback failures).
- Build a **CloudWatch dashboard** for a quick demo in the interview — it photographs well.

### 7.6 Portfolio / viva delivery tips
- Lead with the **zero-static-keys** story and the **two-compute-model** (Lambda + Fargate) decision — they show architectural thinking, not just tool usage.
- Know your **numbers**: region `eu-north-1`, VPC `10.0.0.0/16`, subnets `/20`, ports 3000/3001/5432, Lambda 1024 MB / 60 s, retention 14 days, ECR keeps 3 images.
- Have **one failure story** ready: something broke, how you diagnosed it, what you changed. Interviewers remember stories over definitions.
- Be **honest about gaps** (HTTP-only ALB, SQS stub, unpopulated app secret) and immediately say how you'd fix them. That reads as senior.
- Draw the **architecture on a whiteboard** from memory: Browser → ALB → {Frontend, Backend} → RDS / S3 → Lambda → Backend → WebSocket.

---

# PART 8 — Resource use-case cheat sheet 🧰

| AWS resource | What it's for | Typical real-world use | In this repo |
| :--- | :--- | :--- | :--- |
| **VPC** | Isolated network | Every serious workload | `10.0.0.0/16`, 2 AZs |
| **Subnet** | Network slice per AZ | Tier separation | 2 public + 2 private |
| **IGW** | Inbound internet | Public web tier | Attached to public RT |
| **NAT GW** | Outbound-only internet | Private tasks fetching updates | 1 in dev |
| **SG** | Stateful firewall | Resource access control | ALB→ECS→RDS chain |
| **NACL** | Stateless subnet firewall | Extra/subnet-level control | Not customised |
| **VPC Endpoint** | Private service access | Avoid NAT/internet | S3 Gateway |
| **S3** | Object storage | Media, backups, state, static sites | images + TF state |
| **ECR** | Container registry | App image versions | 3 repos |
| **RDS** | Managed SQL DB | Transactional data | Postgres metadata |
| **Secrets Manager** | Secret store + rotation | DB creds, API keys | callback/app/RDS |
| **ECS Fargate** | Serverless containers | APIs, web apps, workers | backend + frontend |
| **ALB** | Layer 7 load balancer | Routing, WebSocket, TLS | path routing + stickiness |
| **Lambda** | Serverless functions | Event processing | image compression |
| **CloudWatch** | Logs + metrics + alarms | Monitoring & debugging | log groups, 14d |
| **IAM** | Access control | AuthN/AuthZ everywhere | roles + policies |
| **OIDC provider** | Keyless CI identity | GitHub→AWS | 5 roles |
| **SQS** (planned) | Message queue | Async decoupling | stub |
| **Route 53 / ACM / CloudFront** (future) | DNS / TLS / CDN | Domain, HTTPS, global speed | not yet |

---

# PART 9 — Final viva checklist ✅

**Before you walk in, be able to:**
- [ ] Draw the end-to-end flow from memory (upload → process → notify).
- [ ] Name the **region, VPC CIDR, subnet sizes, ports, and Lambda specs**.
- [ ] Explain **why Lambda AND Fargate** (that's the signature decision).
- [ ] Explain **how many S3 buckets** (2) and **why the state bucket is separate**.
- [ ] Explain **CORS**, including *what the URL in the policy is* (the allowed web origin).
- [ ] Explain **Glacier** and the storage-class ladder.
- [ ] Explain **`use_lockfile` vs DynamoDB** for state locking.
- [ ] Explain **`for_each` vs `count`** with a concrete risk.
- [ ] Explain **task role vs execution role**.
- [ ] Explain **Multi-AZ vs Read Replica**.
- [ ] Explain **OIDC and why the `sub` condition matters**.
- [ ] Explain **presigned URLs and why the backend doesn't proxy images**.
- [ ] State **two real gaps** and their fixes without being asked.
- [ ] Walk through **one debugging story**.

---

> **Closing line for any tough question:**
> *"The way I think about it is: what problem does this solve, what does it cost me in money or complexity, and what's the safer default? Then I pick the option that matches the environment — dev optimises for cost, prod for reliability and security."*

Good luck, Ali. 🚀
