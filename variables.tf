variable "name" {
  description = "Name prefix for resources"
  type        = string
  default     = "langfuse"
}

variable "domain" {
  description = "Domain name used for resource naming"
  type        = string
}

variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "westeurope"
}

variable "virtual_network_address_prefix" {
  type        = string
  description = "VNET address prefix."
  default     = "10.224.0.0/12"
}

variable "aks_subnet_address_prefix" {
  description = "Subnet address prefix."
  type        = string
  default     = "10.224.0.0/16"
}

variable "app_gateway_subnet_address_prefix" {
  type        = string
  description = "Subnet address prefix."
  default     = "10.225.0.0/16"
}

variable "db_subnet_address_prefix" {
  description = "Subnet address prefix."
  type        = string
  default     = "10.226.0.0/24"
}

variable "redis_subnet_address_prefix" {
  description = "Subnet address prefix."
  type        = string
  default     = "10.226.1.0/24"
}

variable "storage_subnet_address_prefix" {
  description = "Subnet address prefix."
  type        = string
  default     = "10.226.2.0/24"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.32"
}

variable "aks_service_cidr" {
  type        = string
  description = "The Network Range used by the Kubernetes service."
  default     = "192.168.0.0/20"
}

variable "aks_dns_service_ip" {
  type        = string
  description = "IP address within the Kubernetes service address range that will be used by cluster service discovery (kube-dns)."
  default     = "192.168.0.10"
}

variable "use_encryption_key" {
  description = "Whether or not to use an Encryption key for LLM API credential and integration credential store"
  type        = bool
  default     = true
}

variable "node_pool_vm_size" {
  description = "VM size for AKS node pool"
  type        = string
  default     = "Standard_D8s_v6"
}

variable "node_pool_min_count" {
  description = "Minimum number of nodes in the AKS node pool"
  type        = number
  default     = 2
}

variable "node_pool_max_count" {
  description = "Maximum number of nodes in the AKS node pool"
  type        = number
  default     = 10
}

variable "postgres_instance_count" {
  description = "Number of PostgreSQL instances to create"
  type        = number
  default     = 2 # Default to 2 instances for high availability
}

variable "postgres_ha_mode" {
  description = "HA Mode to use for Postgres. Ensure this is supported in your region https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview#azure-regions"
  type        = string
  default     = "SameZone"
}

variable "postgres_sku_name" {
  description = "SKU name for Azure Database for PostgreSQL"
  type        = string
  default     = "GP_Standard_D2s_v3"
}

variable "postgres_storage_mb" {
  description = "Maximum storage size in MB for PostgreSQL"
  type        = number
  default     = 32768
}

variable "redis_sku_name" {
  description = "SKU name for Azure Managed Redis. See https://learn.microsoft.com/en-us/azure/redis/overview#choosing-the-right-tier for options. Common values: Balanced_B0 (dev/test), Balanced_B1, Balanced_B3, Balanced_B5 (production)."
  type        = string
  default     = "Balanced_B3"

  validation {
    condition     = can(regex("^(Balanced_B[0-9]+|ComputeOptimized_X[0-9]+|FlashOptimized_A[0-9]+|MemoryOptimized_M[0-9]+)$", var.redis_sku_name))
    error_message = "redis_sku_name must be a valid Azure Managed Redis SKU (e.g., Balanced_B0, Balanced_B1, ComputeOptimized_X3, MemoryOptimized_M10)."
  }
}

variable "redis_high_availability" {
  description = "Enable high availability for Azure Managed Redis. Recommended for production workloads."
  type        = bool
  default     = true
}

variable "app_gateway_capacity" {
  description = "Capacity for the Application Gateway"
  type        = number
  default     = 1
}

variable "use_ddos_protection" {
  description = "Wheter or not to use a DDoS protection plan"
  type        = bool
  default     = true
}

variable "clickhouse_replicas" {
  description = "Number of ClickHouse replicas (single shard). The default of 3 provides a highly available setup. Only used when ClickHouse is deployed in-cluster."
  type        = number
  default     = 3

  validation {
    condition     = var.clickhouse_replicas >= 1
    error_message = "clickhouse_replicas must be at least 1."
  }
}

variable "clickhouse_keeper_replicas" {
  description = "Number of ClickHouse Keeper replicas. Must be 1, 3 or 5 to maintain quorum. Only used when ClickHouse is deployed in-cluster."
  type        = number
  default     = 3

  validation {
    condition     = contains([1, 3, 5], var.clickhouse_keeper_replicas)
    error_message = "clickhouse_keeper_replicas must be 1, 3 or 5."
  }
}

variable "clickhouse_storage_size" {
  description = "Size of the persistent volume of each ClickHouse replica"
  type        = string
  default     = "100Gi"
}

variable "clickhouse_keeper_storage_size" {
  description = "Size of the persistent volume of each ClickHouse Keeper replica"
  type        = string
  default     = "10Gi"
}

variable "clickhouse_storage_class" {
  description = "StorageClass used for the ClickHouse and ClickHouse Keeper volumes"
  type        = string
  default     = "managed-csi-premium"
}

variable "clickhouse_resources" {
  description = "Resource requests and limits for each ClickHouse replica"
  type = object({
    cpu    = optional(string, "2")
    memory = optional(string, "8Gi")
  })
  default = {}
}

variable "clickhouse_operator_chart_version" {
  description = "Version of the ClickHouse operator Helm chart (oci://ghcr.io/clickhouse/clickhouse-operator-helm). The default matches the version the Langfuse Helm chart is tested against."
  type        = string
  default     = "0.0.5"
}

variable "cert_manager_chart_version" {
  description = "Version of the cert-manager Helm chart. cert-manager issues the certificates for the ClickHouse operator admission webhooks."
  type        = string
  default     = "v1.20.2"
}

variable "external_clickhouse" {
  description = "Use an external ClickHouse deployment (e.g. ClickHouse Cloud) instead of deploying ClickHouse into the AKS cluster. Set external_clickhouse_password as well. Prefix the host with https:// to connect via HTTPS. The defaults match ClickHouse Cloud; set cluster_enabled = false for ClickHouse Cloud on Azure or single-node deployments."
  type = object({
    host            = string
    http_port       = optional(number, 8443)
    native_port     = optional(number, 9440)
    username        = optional(string, "default")
    database        = optional(string, "default")
    cluster_enabled = optional(bool, true)
    migration_ssl   = optional(bool, true)
  })
  default = null
}

variable "external_clickhouse_password" {
  description = "Password for the external ClickHouse user. Required when external_clickhouse is set."
  type        = string
  default     = ""
  sensitive   = true
}

variable "langfuse_helm_chart_version" {
  description = "Version of the Langfuse Helm chart to deploy"
  type        = string
  default     = "2.1.3"
}

variable "app_version" {
  description = "Langfuse application version (Docker image tag) to deploy, e.g. \"4.46.0\". See https://github.com/langfuse/langfuse/releases."
  type        = string
  default     = "4.46.0"
}

# Kno2: maintenance switch for data migrations. The chart resolves each
# component's replicas as `web.replicas | default langfuse.replicas`, and Helm's
# `default` treats 0 as unset, so web/worker cannot be zeroed individually;
# setting the top-level langfuse.replicas is the only way to reach 0.
variable "langfuse_replicas" {
  description = "Override the replica count of both langfuse-web and langfuse-worker (sets langfuse.replicas in the Helm chart). Set to 0 to stop Langfuse during maintenance; leave null for the chart default."
  type        = number
  default     = null
}

variable "additional_env" {
  description = "Additional environment variables to pass to the Langfuse deployment"
  type = list(object({
    name  = string
    value = optional(string)
    valueFrom = optional(object({
      secretKeyRef = optional(object({
        name = string
        key  = string
      }))
      configMapKeyRef = optional(object({
        name = string
        key  = string
      }))
    }))
  }))
  default = []

  validation {
    condition = alltrue([
      for env in var.additional_env : (env.value != null) != (env.valueFrom != null)
    ])
    error_message = "Each environment variable must have either 'value' or 'valueFrom' specified, but not both."
  }
}

variable "ssl_certificate_secret_id" {
  description = "Azure Key Vault secret ID for an existing SSL certificate. If provided, the module will use this certificate instead of creating a self-signed one. The Application Gateway managed identity must have access to this Key Vault."
  type        = string
  default     = null
}

variable "signup_disabled" {
  description = "Disable public sign up (sets langfuse.features.signUpDisabled in the Helm chart)"
  type        = bool
  default     = false
}

variable "smtp_connection_value" {
  description = "SMTP connection URL for email sending (sets additionalEnv entry in the Helm chart). Example: smtps://user:"
  type        = string
  sensitive   = true
  default     = null
}

# Entra ID (Azure AD) SSO. Rendered through the chart's first-class
# langfuse.auth.providers.azureAd values, NOT additional_env: the chart's
# nextauthEnv helper already emits AUTH_AZURE_AD_* and AUTH_DISABLE_USERNAME_PASSWORD,
# so routing them through additionalEnv would create duplicate env entries that
# Helm's strategic merge collapses.
variable "azure_ad_client_id" {
  description = "Application (client) ID of the Entra ID app registration used for SSO. Set to null to leave SSO unconfigured."
  type        = string
  default     = null
}

variable "azure_ad_tenant_id" {
  description = "Entra ID directory (tenant) ID for the SSO app registration."
  type        = string
  default     = null
}

variable "azure_ad_client_secret_value" {
  description = "Client secret for the Entra ID app registration. Stored in the 'langfuse' Kubernetes secret and referenced by secretKeyRef, never rendered into Helm values."
  type        = string
  sensitive   = true
  default     = null
}

variable "azure_ad_allow_account_linking" {
  description = "Allow an Entra ID sign-in to link to an existing Langfuse account with the same email address. Required when migrating existing email/password users to SSO."
  type        = bool
  default     = true
}

variable "disable_username_password" {
  description = "Disable email/password sign-in, leaving SSO as the only auth path (sets langfuse.auth.disableUsernamePassword). Only enable after verifying SSO sign-in works, or you will lock yourself out."
  type        = bool
  default     = false
}
