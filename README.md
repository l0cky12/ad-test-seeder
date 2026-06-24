# AD Test Seeder

Populates a test Active Directory domain with a **realistic fake company** — multiple offices, departments, role-based groups, and tiered admin accounts. Designed for testing AD-dependent tools (Snipe-IT, PaperCut, Intune, reporting, audits) against a dataset that looks like a real organization.

## What It Creates

| Object Type       | Default Count | Details                                              |
|-------------------|---------------|------------------------------------------------------|
| OUs               | ~100          | Office → Department hierarchy, computer types, extras |
| Users             | 1,000         | Across 5 offices, 12 departments, real attributes    |
| Computers         | 1,000         | Workstations, laptops, servers, tablets — varied OS  |
| Groups            | 100           | Department, office, role-based, resource access       |
| Contacts          | 50            | External mail contacts (vendors, contractors)        |
| Service Accounts  | 5             | Password never expires, cannot change password       |
| Admin Accounts    | 4             | Tier-0/1/2 with group membership                      |
| **Total**         | **~2,260**    |                                                       |

## Company Structure

```
Contoso Corp (test.lan)
├── Users
│   ├── HQ-NYC (New York)
│   │   ├── IT
│   │   ├── Finance
│   │   ├── HR
│   │   ├── Sales
│   │   └── ... (12 departments)
│   ├── BRANCH-LAX (Los Angeles)
│   │   └── ... (12 departments)
│   ├── BRANCH-CHI (Chicago)
│   ├── BRANCH-HOU (Houston)
│   └── REMOTE-EU (London)
├── Computers
│   ├── HQ-NYC
│   │   ├── Workstations
│   │   ├── Servers
│   │   └── Kiosks
│   ├── BRANCH-LAX
│   │   └── ...
│   └── ... (per office)
├── Groups
├── Contacts
├── ServiceAccounts
├── AdminAccounts
├── ComputerLabs
├── TrainingRooms
├── SharedDevices
└── ConferenceRooms
```

## Offices

| Code         | City          | Weight | ~Users |
|--------------|---------------|--------|--------|
| HQ-NYC       | New York      | 35%    | ~350   |
| BRANCH-LAX   | Los Angeles   | 20%    | ~200   |
| BRANCH-CHI   | Chicago       | 18%    | ~180   |
| BRANCH-HOU   | Houston       | 15%    | ~150   |
| REMOTE-EU    | London (UK)   | 12%    | ~120   |

## Departments

IT, Finance, HR, Sales, Marketing, Operations, Legal, Engineering, Support, Facilities, Security, R&D

Each department has realistic job titles (e.g., IT → Helpdesk Technician, Systems Administrator, Network Engineer, Security Analyst, IT Manager, IT Director).

## Groups

| Type                | Example                          | Count |
|---------------------|----------------------------------|-------|
| Department per office| `GG-HQ-NYC-IT-Users`           | 60    |
| Office-wide          | `GG-HQ-NYC-AllStaff`           | 5     |
| Department global    | `GG-IT-Global`                 | 12    |
| Role-based           | `GG-Role-Managers`             | 8     |
| Resource access      | `SG-VPN-Access`                | 10    |
| Custom/pad           | `SG-Custom-N`                  | 5     |

## Admin Tiers

| Account               | Tier | Groups                                                    |
|-----------------------|------|-----------------------------------------------------------|
| `adm-t0-enterprise`   | T0   | Enterprise Admins, Domain Admins, Schema Admins          |
| `adm-t0-da`           | T0   | Domain Admins                                             |
| `adm-t1-server`       | T1   | Server Operators                                          |
| `adm-t2-helpdesk`     | T2   | Account Operators                                         |

## Prerequisites

- **ActiveDirectory PowerShell module** (RSAT on workstation, or built-in on DC)
- **Domain-joined machine** in the target test domain
- **Domain Admin** (or account with delegated OU permissions)
- PowerShell 5.1+ or PowerShell 7+

## Execution Policy

If you get a "not digitally signed" error (common when downloading from GitHub):

```powershell
# Option 1 — Unblock + run with bypass (one-time)
Unblock-File .\Populate-TestAD.ps1
powershell -ExecutionPolicy Bypass -File .\Populate-TestAD.ps1

# Option 2 — Set policy for current session only
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\Populate-TestAD.ps1

# Option 3 — Run directly with bypass + parameters
powershell -ExecutionPolicy Bypass -File .\Populate-TestAD.ps1 -CleanFirst -UserCount 500
```

The script also auto-unblocks itself on first run. After that, subsequent runs won't need the bypass flag.

## Quick Start

```powershell
# Full company — 1K users, 1K PCs, 100 groups, 100 OUs
.\Populate-TestAD.ps1

# Wipe previous run and re-seed
.\Populate-TestAD.ps1 -CleanFirst

# Smaller scale for quick testing
.\Populate-TestAD.ps1 -UserCount 100 -ComputerCount 50 -GroupCount 20

# Larger scale — 5K users, 3K computers
.\Populate-TestAD.ps1 -UserCount 5000 -ComputerCount 3000 -CleanFirst
```

## Parameters

| Parameter              | Type   | Default          | Description                          |
|------------------------|--------|------------------|--------------------------------------|
| `DomainFQDN`           | string | `test.lan`       | FQDN of target domain                |
| `NetBIOS`              | string | `TEST`           | NetBIOS name                         |
| `UserCount`            | int    | `1000`           | Number of user accounts              |
| `ComputerCount`        | int    | `1000`           | Number of computer accounts          |
| `GroupCount`           | int    | `100`            | Number of security groups            |
| `OUCount`              | int    | `100`            | Target OU count                      |
| `ServiceAccountCount`  | int    | `5`              | Service accounts                     |
| `DomainAdminCount`     | int    | `4`              | Tiered admin accounts                |
| `Password`             | string | `TempP@ssw0rd!`  | Password for all accounts            |
| `CleanFirst`           | switch | —                | Remove test OUs before creating      |

## User Attributes

Each user gets realistic AD attributes:

- **Name:** Random first + last name (3,584 unique combinations)
- **Title:** Department-specific (e.g., IT → "Network Engineer")
- **Department:** One of 12 departments
- **Company:** Contoso Corp
- **Email:** `jsmith@test.lan`
- **Office location:** Street, City, State, ZIP, Country
- **Group membership:** Department group + office group + role group (if applicable)
- **OU placement:** `Users/{Office}/{Department}/`

## Computer Attributes

- **Name:** `WS-00001`, `LT-00042`, `SRV-00100`, etc.
- **OS:** Windows 11 Pro, Windows 10 Pro, Windows Server 2022, etc.
- **Type:** Workstation, Laptop, Tablet, Server, Virtual
- **OU placement:** `Computers/{Office}/{Workstations|Servers|Kiosks}/`
- **Description:** Type, office, OS

## Cleanup

```powershell
# Wipe and re-seed
.\Populate-TestAD.ps1 -CleanFirst

# Manual cleanup — remove entire company OU
Get-ADOrganizationalUnit -Filter "Name -eq 'Contoso'" |
    Remove-ADOrganizationalUnit -Recursive -Confirm:$false
```

## ⚠️ Warning

**Do not run this in a production domain.** It creates thousands of objects with a known password. This is for isolated lab environments only.

## License

MIT
