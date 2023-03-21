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

data "coder_parameter" "admin_password" {
  name = "Administrator password for logging in via RDP"
  description = "Must meet Windows password complexity requirements: https://docs.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/password-must-meet-complexity-requirements#reference"
  default = "Hunter2!Hunter2"
  mutable = true
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
    serial-port-enable         = "TRUE"
    windows-startup-script-ps1 = <<EOF

    # Install Chocolatey package manager before
    # the agent starts to use via startup_script
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    # Reload path so sessions include "choco" and "refreshenv"
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    # Install Git and reload path
    choco install -y git -params '"/GitAndUnixToolsOnPath /WindowsTerminal"'
    choco install -y git-credential-manager-for-windows
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    # start Coder agent init script (see startup_script above)
    ${coder_agent.main.init_script}

    EOF
  }
}


resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = google_compute_instance.dev[0].id

  item {
    key       = "Administrator password"
    value     = data.coder_parameter.admin_password.value
    sensitive = true
  }  

  item {
    key   = "image"
    value = data.coder_parameter.gcp_image.value
  }  

  item {
    key   = "zone"
    value = data.coder_parameter.gcp_zone.value
  }

  item {
    key   = "project"
    value = data.coder_parameter.gcp_project_id.value
  }


}

resource "coder_agent" "main" {
  auth = "google-instance-identity"
  arch = "amd64"
  os   = "windows"
  
  login_before_ready = false
  
  startup_script = <<EOF
    # Set admin password and enable admin user (must be in this order)
    Get-LocalUser -Name "Administrator" | Set-LocalUser -Password (ConvertTo-SecureString -AsPlainText "${data.coder_parameter.admin_password.value}" -Force)
    Get-LocalUser -Name "Administrator" | Enable-LocalUser

    # Enable RDP
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0

    # Enable RDP through Windows Firewall
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    choco feature enable -n=allowGlobalConfirmation

    #--- Apps ---
    choco install -y 7zip
    choco install -y 7zip.commandline
    choco install -y ack
    choco install -y curl
    choco install -y fiddler
    choco install -y filezilla
    choco install -y paint.net
    choco install -y sudo

    #--- Browsers ---
    choco install -y firefox
    choco install -y firefox-dev
    choco install -y googlechrome
    choco install -y googlechrome.canary
    choco install -y microsoft-edge

    #--- Sysadmin ---
    choco install -y putty
    choco install -y sysinternals
    choco install -y windirstat
    choco install -y winscp

    #--- Development ---
    choco install -y dotpeek
    choco install -y linqpad5
    
    choco install -y java.jdk
    choco install -y javaruntime

    choco install -y visualstudiocode-insiders
    choco install -y vscode

    choco install -y microsoft-windows-terminal

    Install-Module posh-git -Scope CurrentUser -Force -SkipPublisherCheck
    Install-Module oh-my-posh -Scope CurrentUser -Force -SkipPublisherCheck
    Install-Module -Name PSReadLine -Scope CurrentUser -Force -SkipPublisherCheck

    echo "Import-Module posh-git" > $PROFILE
    echo "Import-Module oh-my-posh" >> $PROFILE
    echo "Set-Theme Paradox" >> $PROFILE

    # Hide Search button / box
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Type DWord -Value 0

    # Hide Task View button
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Type DWord -Value 0

    # Show titles in taskbar
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarGlomLevel" -Type DWord -Value 1

    # Show small icons in taskbar
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarSmallIcons" -Type DWord -Value 1

    # Show known file extensions
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Type DWord -Value 0

    # Show hidden files
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Type DWord -Value 1

    # Show Computer shortcut on desktop
    If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu")) {
      New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu" | Out-Null
    }
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu" -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Type DWord -Value 0

EOF

}

resource "coder_metadata" "home_info" {
  resource_id = google_compute_disk.root.id

  item {
    key   = "size"
    value = "${google_compute_disk.root.size} GiB"
  }
}
