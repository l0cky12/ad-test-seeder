# AD Test Seeder

Populates a test Active Directory domain with realistic fake objects — OUs, users, computers, groups, contacts, service accounts, and tiered admin accounts.

Designed for **lab / development environments only**. Useful for testing tools like Snipe-IT, PaperCut, Intune, reporting scripts, or any AD-dependent workflow against a realistic dataset.

## What It Creates

| Object Type       | Default Count | Notes                                              |
|-------------------|---------------|----------------------------------------------------|
| OUs               | ~20           | Department OUs under `TestLab\Users`               |
| Users             | 50            | Random names, titles, departments, group membership |
| Computers         | 30            | Workstations + servers, varied OSes               |
| Groups            | ~40           | Global, DomainLocal, and per-department groups     |
| Contacts          | 10            | External mail contacts                             |
| Service Accounts  | 5             | Password never expires, cannot change password     |
| Admin Accounts    | 3             | Tier-0/1/2 with group membership                   |

## Prerequisites

- **ActiveDirectory PowerShell module** (RSAT on workstation, or built-in on DC)
- **Domain-joined machine** in the target test domain
- **Domain Admin** (or account with delegated OU permissions)
- PowerShell 5.1+ (Windows PowerShell) or PowerShell 7+

## Quick Start

```powershell
# Default: 50 users, 30 computers in test.lan
.\Populate-TestAD.ps1

# Custom domain with more objects
.\Populate-TestAD.ps1 -DomainFQDN lab.local -UserCount 200 -ComputerCount 100

# Wipe previous run and re-seed
.\Populate-TestAD.ps1 -CleanFirst

# Everything custom
.\Populate-TestAD.ps1 `
    -DomainFQDN test.lan `
    -UserCount 100 `
    -ComputerCount 50 `
    -GroupsPerOU 5 `
    -ContactCount 20 `
    -ServiceAccountCount 10 `
    -Password 'MyP@ss123!' `
    -CleanFirst
```

## Parameters

| Parameter              | Type     | Default          | Description                          |
|------------------------|----------|------------------|--------------------------------------|
| `DomainFQDN`           | string   | `test.lan`       | FQDN of target domain                |
| `NetBIOS`              | string   | `TEST`           | NetBIOS name                         |
| `UserCount`            | int      | `50`             | Number of user accounts              |
| `ComputerCount`        | int      | `30`             | Number of computer accounts          |
| `GroupsPerOU`          | int      | `3`              | Security groups per prefix per round |
| `ContactCount`         | int      | `10`             | Mail contacts                        |
| `ServiceAccountCount`  | int      | `5`              | Service accounts                     |
| `Password`             | string   | `TempP@ssw0rd!`  | Password for all accounts            |
| `CleanFirst`           | switch   | —                | Remove test OUs before creating      |

## OU Structure

```
test.lan
└── TestLab
    ├── Users
    │   ├── IT
    │   ├── Finance
    │   ├── HR
    │   ├── Sales
    │   ├── Marketing
    │   ├── Operations
    │   ├── Legal
    │   ├── Engineering
    │   ├── Support
    │   └── Facilities
    ├── Computers
    │   ├── Servers
    │   └── Workstations
    ├── Groups
    ├── Contacts
    ├── ServiceAccounts
    └── AdminAccounts
```

## Cleanup

Use `-CleanFirst` to remove all OUs named `Test*` and their child objects before re-seeding:

```powershell
.\Populate-TestAD.ps1 -CleanFirst
```

Or manually remove everything under the `TestLab` OU:

```powershell
Get-ADOrganizationalUnit -Filter "Name -eq 'TestLab'" |
    Remove-ADOrganizationalUnit -Recursive -Confirm:$false
```

## ⚠️ Warning

**Do not run this in a production domain.** It creates hundreds of objects with a known password. This is for isolated lab environments only.
