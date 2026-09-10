variable "region" {
  description = "AWS region for the whole POC"
  type        = string
  default     = "eu-west-2"
}

variable "azs" {
  description = "Availability zones used by both VPCs"
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b"]
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "node_instance_types" {
  description = "Instance types for EKS managed node groups"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "gateway_vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "backend_vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}
