variable "name" {
  description = "VPC name (vpc-gateway / vpc-backend)"
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "azs" {
  description = "Availability zones (2 required)"
  type        = list(string)
}

variable "public_subnets" {
  description = "Public subnet CIDRs (NAT GW + internet-facing ELB)"
  type        = list(string)
}

variable "private_subnets" {
  description = "Private subnet CIDRs (EKS nodes)"
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster that will live in this VPC (for subnet tagging)"
  type        = string
}
