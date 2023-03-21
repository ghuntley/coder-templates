terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.6.17"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 4.34.0"
    }
  }
}

provider "coder" {
  feature_use_managed_variables = true
}

data "coder_parameter" "gcp_project_id" {
  name = "Which Google Compute Project should your workspace live in?"
  default = "ghuntley-dev"
}

data "coder_parameter" "gcp_zone" {
  name    = "What region should your workspace live in?"
  type    = "string"
  default = "australia-southeast1-a"
  icon    = "/emojis/1f30e.png"
  mutable = false
  option {
    name  = "Sydney, Australia, APAC"
    value = "australia-southeast1-a"
    icon = "/emojis/1f1e6-1f1fa.png"
  }
  option {
    name  = "North America (Central)"
    value = "us-central1-a"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Europe (West)"
    value = "europe-west4-b"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
}

data "coder_parameter" "gcp_machine_type" {
  name    = "What size should your workspace be?"
  type    = "string"
  default = "e2-medium"
  icon    = "/emojis/1f4b0.png"
  mutable = true
  option {
    name  = "e2-medium - 2vcpu - 4gb - $28.32 USD/month"
    value = "e2-medium"
  }
}

data "coder_parameter" "gcp_image" {
  name    = "What edition of Windows Server 2022 should your workspace be?"
  type    = "string"
  default = "windows-server-2022-dc-v20230315"
  icon    = "/emojis/1fa9f.png"
  mutable = true
  option {
    name  = "Desktop"
    value = "windows-server-2022-dc-v20230315"
  }
  option {
    name  = "Core"
    value = "windows-server-2022-dc-core-v20230315"
  }
}

provider "google" {
  zone    = data.coder_parameter.gcp_zone.value
  project = data.coder_parameter.gcp_project_id.value
}

data "coder_workspace" "me" {
}

data "google_compute_default_service_account" "default" {
}

resource "google_compute_disk" "root" {
  name  = "coder-${data.coder_workspace.me.id}-root"
  type  = "pd-ssd"
  zone  = data.coder_parameter.gcp_zone.value
  image = data.coder_parameter.gcp_image.value
  lifecycle {
    ignore_changes = [name, image]
  }
}

resource "coder_agent" "main" {
  auth = "google-instance-identity"
  arch = "amd64"
  os   = "windows"

  login_before_ready = false
}

resource "google_compute_instance" "dev" {
  zone         = data.coder_parameter.gcp_zone.value
  count        = data.coder_workspace.me.start_count
  name         = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
  machine_type = data.coder_parameter.gcp_machine_type.value
  network_interface {
    network = "default"
    access_config {
      // Ephemeral public IP
    }
  }
  boot_disk {
    auto_delete = false
    source      = google_compute_disk.root.name
  }
  service_account {
    email  = data.google_compute_default_service_account.default.email
    scopes = ["cloud-platform"]
  }
  metadata = {
    windows-startup-script-ps1 = coder_agent.main.init_script
    serial-port-enable         = "TRUE"
  }
}
resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = google_compute_instance.dev[0].id

  item {
    key   = "type"
    value = google_compute_instance.dev[0].machine_type
  }
}

resource "coder_metadata" "home_info" {
  resource_id = google_compute_disk.root.id

  item {
    key   = "size"
    value = "${google_compute_disk.root.size} GiB"
  }
}
