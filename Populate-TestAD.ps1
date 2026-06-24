<#
.SYNOPSIS
    Populates a test Active Directory domain with a realistic fake company structure.

.DESCRIPTION
    Creates a multi-office, multi-department company in a test AD domain:
    - 1,000 users across 5 offices and 12 departments
    - 100 OUs (offices, departments, computer labs, etc.)
    - 1,000 computers (workstations, laptops, servers, tablets)
    - 100 security groups (department, office, role-based)
    - 5 service accounts
    - 4 tiered domain admin accounts

    Designed for lab / development environments only.

.PARAMETER DomainFQDN
    FQDN of the test domain (default: test.lan).

.PARAMETER NetBIOS
    NetBIOS name (default: TEST).

.PARAMETER UserCount
    Number of regular users (default: 1000).

.PARAMETER ComputerCount
    Number of computer accounts (default: 1000).

.PARAMETER GroupCount
    Number of security groups (default: 100).

.PARAMETER OUCount
    Target OU count — controls granularity of department/office sub-OUs (default: 100).

.PARAMETER ServiceAccountCount
    Number of service accounts (default: 5).

.PARAMETER DomainAdminCount
    Number of tiered admin accounts (default: 4).

.PARAMETER Password
    Password for all accounts (default: TempP@ssw0rd!).

.PARAMETER CleanFirst
    Remove test OUs before creating new objects.

.EXAMPLE
    .\Populate-TestAD.ps1
    Full company: 1K users, 1K PCs, 100 groups, 100 OUs in test.lan.

.EXAMPLE
    .\Populate-TestAD.ps1 -CleanFirst
    Wipe previous run, re-seed with defaults.

.EXAMPLE
    .\Populate-TestAD.ps1 -UserCount 5000 -ComputerCount 3000
    Larger scale — 5K users, 3K computers.

.NOTES
    Requires: ActiveDirectory PowerShell module
    Run on: Domain-joined machine with RSAT or a Domain Controller
    Permissions: Domain Admin (or delegated OU permissions)
#>

[CmdletBinding()]
param(
    [string]$DomainFQDN = 'test.lan',
    [string]$NetBIOS    = 'TEST',
    [int]$UserCount           = 1000,
    [int]$ComputerCount       = 1000,
    [int]$GroupCount          = 100,
    [int]$OUCount             = 100,
    [int]$ServiceAccountCount = 5,
    [int]$DomainAdminCount    = 4,
    [string]$Password         = 'TempP@ssw0rd!',
    [switch]$CleanFirst
)

# ── Bootstrap ────────────────────────────────────────────────────────────────

Import-Module ActiveDirectory -ErrorAction Stop

$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$domainDN = "DC=$(($DomainFQDN -split '\.' ) -join ',DC=')"

# Tracking
$created = @{ Users = 0; Computers = 0; Groups = 0; Contacts = 0; ServiceAccounts = 0; Admins = 0; OUs = 0 }
$errors  = @()

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Step  { param([string]$Msg) Write-Host "[*] $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "[+] $Msg" -ForegroundColor Green }
function Write-Warn2 { param([string]$Msg) Write-Host "[!] $Msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$Msg) Write-Host "[-] $Msg" -ForegroundColor Red }

function Invoke-Safe {
    param([scriptblock]$Action, [string]$Description)
    try {
        & $Action
    } catch {
        $msg = "$Description : $($_.Exception.Message)"
        $script:errors += $msg
        Write-Err $msg
    }
}

# ── Company Data ──────────────────────────────────────────────────────────────

# 5 offices / sites
$offices = @(
    @{ Name = 'HQ-NYC';        City = 'New York';       State = 'NY'; Country = 'US'; Street = '350 5th Ave';        Zip = '10118' }
    @{ Name = 'BRANCH-LAX';    City = 'Los Angeles';    State = 'CA'; Country = 'US'; Street = '3500 W Olive Ave';   Zip = '90015' }
    @{ Name = 'BRANCH-CHI';    City = 'Chicago';        State = 'IL'; Country = 'US'; Street = '233 S Wacker Dr';    Zip = '60606' }
    @{ Name = 'BRANCH-HOU';    City = 'Houston';        State = 'TX'; Country = 'US'; Street = '1000 McKinney St';   Zip = '77002' }
    @{ Name = 'REMOTE-EU';     City = 'London';         State = '';   Country = 'GB'; Street = '1 Canada Square';    Zip = 'E14 5AB' }
)

# 12 departments
$departments = @(
    'IT','Finance','HR','Sales','Marketing','Operations','Legal','Engineering',
    'Support','Facilities','Security','R&D'
)

# Job titles per department
$jobTitles = @{
    'IT'          = @('Helpdesk Technician','Systems Administrator','Network Engineer','Security Analyst','IT Manager','Database Administrator','DevOps Engineer','IT Director')
    'Finance'     = @('Accountant','Financial Analyst','Payroll Specialist','Finance Manager','Controller','CFO','Bookkeeper','Auditor')
    'HR'          = @('HR Coordinator','Recruiter','HR Generalist','HR Manager','HR Director','Benefits Specialist','Training Specialist')
    'Sales'       = @('Sales Representative','Account Executive','Sales Manager','Regional Sales Director','VP of Sales','Sales Engineer','Business Development Rep')
    'Marketing'   = @('Marketing Specialist','Content Writer','SEO Analyst','Marketing Manager','Brand Manager','CMO','Social Media Manager','Graphic Designer')
    'Operations'  = @('Operations Analyst','Logistics Coordinator','Operations Manager','COO','Supply Chain Specialist','Procurement Analyst')
    'Legal'       = @('Paralegal','Legal Counsel','Compliance Officer','General Counsel','Legal Secretary','Contract Specialist')
    'Engineering' = @('Software Engineer','Senior Software Engineer','Engineering Manager','CTO','QA Engineer','DevOps Engineer','Solutions Architect','Full Stack Developer')
    'Support'     = @('Support Technician','Customer Success Manager','Support Team Lead','Knowledge Base Specialist','Tier 1 Support','Tier 2 Support')
    'Facilities'  = @('Facilities Coordinator','Maintenance Technician','Facilities Manager','Office Manager','Receptionist')
    'Security'    = @('Security Engineer','SOC Analyst','CISO','Security Manager','Penetration Tester','GRC Analyst')
    'R&D'         = @('Research Scientist','R&D Engineer','Product Manager','Innovation Lead','Data Scientist','Lab Technician')
}

# Name pools (64 first names × 56 last names = 3,584 unique combos)
$firstNames = @(
    'James','Mary','Robert','Patricia','John','Jennifer','Michael','Linda',
    'David','Elizabeth','William','Barbara','Richard','Susan','Joseph','Jessica',
    'Thomas','Sarah','Charles','Karen','Christopher','Nancy','Daniel','Margaret',
    'Matthew','Lisa','Anthony','Betty','Mark','Sandra','Donald','Ashley',
    'Steven','Kimberly','Paul','Emily','Andrew','Donna','Joshua','Michelle',
    'Kenneth','Carol','Kevin','Amanda','Brian','Dorothy','George','Melissa',
    'Edward','Deborah','Ronald','Stephanie','Timothy','Rebecca','Jason','Sharon',
    'Jeffrey','Laura','Ryan','Cynthia','Jacob','Kathleen','Gary','Amy'
)
$lastNames = @(
    'Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis',
    'Rodriguez','Martinez','Hernandez','Lopez','Gonzalez','Wilson','Anderson',
    'Thomas','Taylor','Moore','Jackson','Martin','Lee','Perez','Thompson',
    'White','Harris','Sanchez','Clark','Ramirez','Lewis','Robinson','Walker',
    'Young','Allen','King','Wright','Scott','Torres','Nguyen','Hill','Flores',
    'Green','Adams','Nelson','Baker','Hall','Rivera','Campbell','Mitchell',
    'Carter','Roberts','Gomez','Phillips','Evans','Turner','Diaz','Parker'
)

# Computer data
$computerPrefixes = @(
    @{ Prefix = 'WS';  Type = 'Workstation'; OS = 'Windows 11 Pro';         OUType = 'Workstations' }
    @{ Prefix = 'LT';  Type = 'Laptop';      OS = 'Windows 11 Pro';         OUType = 'Workstations' }
    @{ Prefix = 'TBL'; Type = 'Tablet';      OS = 'Windows 11 Enterprise';  OUType = 'Workstations' }
    @{ Prefix = 'SRV'; Type = 'Server';      OS = 'Windows Server 2022';    OUType = 'Servers' }
    @{ Prefix = 'VM';  Type = 'Virtual';     OS = 'Windows Server 2019';    OUType = 'Servers' }
    @{ Prefix = 'WS';  Type = 'Workstation'; OS = 'Windows 10 Pro';         OUType = 'Workstations' }
    @{ Prefix = 'LT';  Type = 'Laptop';      OS = 'Windows 10 Enterprise';  OUType = 'Workstations' }
)

$companyName = 'Contoso Corp'

# Service account names
$svcNames = @('sql-svc','web-svc','backup-svc','sync-svc','report-svc','adconnect-svc','papercut-svc','snipeit-svc','monitor-svc','agent-svc')

# Admin tier definitions
$adminTiers = @(
    @{ Name = 'adm-t0-enterprise'; Desc = 'Tier-0 Enterprise Admin'; Groups = @('Enterprise Admins','Domain Admins','Schema Admins') }
    @{ Name = 'adm-t0-da';         Desc = 'Tier-0 Domain Admin';      Groups = @('Domain Admins') }
    @{ Name = 'adm-t1-server';     Desc = 'Tier-1 Server Admin';      Groups = @('Server Operators') }
    @{ Name = 'adm-t2-helpdesk';   Desc = 'Tier-2 Helpdesk';          Groups = @('Account Operators') }
    @{ Name = 'adm-t2-desktop';    Desc = 'Tier-2 Desktop Support';   Groups = @('Account Operators') }
)

# ── Clean ─────────────────────────────────────────────────────────────────────

if ($CleanFirst) {
    Write-Step "Cleaning previous test objects under $domainDN ..."
    $testOUs = Get-ADOrganizationalUnit -Filter "Name -like 'Test*' -or Name -like 'Contoso*'" -SearchBase $domainDN -ErrorAction SilentlyContinue
    foreach ($ou in $testOUs) {
        Invoke-Safe {
            if ($ou.DistinguishedName -ne $domainDN) {
                Get-ADUser -Filter * -SearchBase $ou.DistinguishedName -ErrorAction SilentlyContinue |
                    Remove-ADUser -Confirm:$false
                Get-ADComputer -Filter * -SearchBase $ou.DistinguishedName -ErrorAction SilentlyContinue |
                    Remove-ADComputer -Confirm:$false
                Get-ADGroup -Filter * -SearchBase $ou.DistinguishedName -ErrorAction SilentlyContinue |
                    Remove-ADGroup -Confirm:$false
                Get-ADObject -Filter * -SearchBase $ou.DistinguishedName -ErrorAction SilentlyContinue |
                    Where-Object { $_.ObjectClass -eq 'contact' } |
                    Remove-ADObject -Confirm:$false
                Remove-ADOrganizationalUnit -Identity $ou.DistinguishedName -Confirm:$false -Recursive
                Write-Ok "Removed OU: $($ou.Name)"
            }
        } "Clean OU $($ou.Name)"
    }
}

# ── OU Structure ──────────────────────────────────────────────────────────────

Write-Step "Building OU structure (target: $OUCount OUs)"

# Root company OU
$rootOUName = $companyName.Split(' ')[0]  # "Contoso"
$rootOU     = "OU=$rootOUName,$domainDN"

Invoke-Safe {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$rootOUName'" -SearchBase $domainDN -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $rootOUName -Path $domainDN -Description "$companyName root OU" -ErrorAction Stop
    }
    $script:created.OUs++
} "Create root OU $rootOUName"

# Top-level OUs under root
$topLevelOUs = @('Users','Computers','Groups','Contacts','ServiceAccounts','AdminAccounts')
foreach ($ouName in $topLevelOUs) {
    Invoke-Safe {
        $ouPath = "OU=$ouName,$rootOU"
        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$ouName'" -SearchBase $rootOU -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $ouName -Path $rootOU -Description "$companyName $ouName" -ErrorAction Stop
        }
        $script:created.OUs++
    } "Create top-level OU $ouName"
}

# ── Office OUs (under Computers) ──
$computersOU = "OU=Computers,$rootOU"
$usersOU     = "OU=Users,$rootOU"
$groupsOU    = "OU=Groups,$rootOU"
$contactsOU  = "OU=Contacts,$rootOU"
$svcOU       = "OU=ServiceAccounts,$rootOU"
$adminOU     = "OU=AdminAccounts,$rootOU"

# Per-office computer sub-OUs (Servers, Workstations per office)
foreach ($office in $offices) {
    Invoke-Safe {
        $officePath = "OU=$($office.Name),$computersOU"
        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$($office.Name)'" -SearchBase $computersOU -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $office.Name -Path $computersOU -Description "$($office.City) office computers" -ErrorAction Stop
        }
        $script:created.OUs++
    } "Create office computer OU $($office.Name)"

    # Sub-OUs for computer types
    foreach ($compType in @('Workstations','Servers','Kiosks')) {
        Invoke-Safe {
            $typePath = "OU=$compType,OU=$($office.Name),$computersOU"
            if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$compType'" -SearchBase "OU=$($office.Name),$computersOU" -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name $compType -Path "OU=$($office.Name),$computersOU" -Description "$compType for $($office.Name)" -ErrorAction Stop
            }
            $script:created.OUs++
        } "Create $compType OU for $($office.Name)"
    }
}

# ── Department OUs (under Users, per office) ──
# This creates office → department sub-OUs for users
# 5 offices × 12 departments = 60 user OUs (plus the top-level and computer OUs)
$officeDeptOUs = @{}
foreach ($office in $offices) {
    $officeUserOU = "OU=$($office.Name),$usersOU"
    Invoke-Safe {
        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$($office.Name)'" -SearchBase $usersOU -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $office.Name -Path $usersOU -Description "$($office.City) users" -ErrorAction Stop
        }
        $script:created.OUs++
    } "Create office user OU $($office.Name)"

    foreach ($dept in $departments) {
        $deptOU = "OU=$dept,$officeUserOU"
        $officeDeptOUs["$($office.Name)|$dept"] = $deptOU
        Invoke-Safe {
            if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$dept'" -SearchBase $officeUserOU -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name $dept -Path $officeUserOU -Description "$dept dept - $($office.Name)" -ErrorAction Stop
            }
            $script:created.OUs++
        } "Create dept OU $dept for $($office.Name)"
    }
}

# ── Extra OUs to hit 100 target ──
# Computer labs, training rooms, shared devices, conference rooms, break-glass
$extraOUs = @(
    @{ Name = 'ComputerLabs';   Parent = $computersOU;  Desc = 'Computer lab machines' }
    @{ Name = 'TrainingRooms';  Parent = $computersOU;  Desc = 'Training room PCs' }
    @{ Name = 'SharedDevices';  Parent = $computersOU;  Desc = 'Shared/kiosk devices' }
    @{ Name = 'ConferenceRooms';Parent = $computersOU;  Desc = 'Conference room PCs' }
    @{ Name = 'BreakGlass';     Parent = $rootOU;       Desc = 'Break-glass admin accounts' }
    @{ Name = 'Mailboxes';      Parent = $rootOU;       Desc = 'Shared mailboxes' }
    @{ Name = 'SecurityGroups'; Parent = $rootOU;       Desc = 'Additional security groups' }
    @{ Name = 'DistributionLists'; Parent = $rootOU;    Desc = 'Distribution lists' }
    @{ Name = 'ServiceAccounts-Archive'; Parent = $rootOU; Desc = 'Archived service accounts' }
)

foreach ($extra in $extraOUs) {
    if ($created.OUs -ge $OUCount) { break }
    Invoke-Safe {
        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$($extra.Name)'" -SearchBase $extra.Parent -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $extra.Name -Path $extra.Parent -Description $extra.Desc -ErrorAction Stop
        }
        $script:created.OUs++
    } "Create extra OU $($extra.Name)"
}

Write-Ok "OU structure complete: $($created.OUs) OUs created"

# ── Groups ────────────────────────────────────────────────────────────────────

Write-Step "Creating $GroupCount security groups"

$groupDefs = @()

# 1. Department groups (per office) — GG-{Office}-{Dept}-Users
foreach ($office in $offices) {
    foreach ($dept in $departments) {
        $groupDefs += @{
            Name = "GG-$($office.Name)-$dept-Users"
            Scope = 'Global'
            Desc  = "$dept users - $($office.City)"
            Path  = $groupsOU
        }
    }
}

# 2. Office-wide groups — GG-{Office}-All-Staff
foreach ($office in $offices) {
    $groupDefs += @{
        Name = "GG-$($office.Name)-AllStaff"
        Scope = 'Global'
        Desc  = "All staff - $($office.City)"
        Path  = $groupsOU
    }
}

# 3. Department-wide groups (cross-office) — GG-{Dept}-Global
foreach ($dept in $departments) {
    $groupDefs += @{
        Name = "GG-$dept-Global"
        Scope = 'Global'
        Desc  = "All $dept staff (all offices)"
        Path  = $groupsOU
    }
}

# 4. Role-based groups
$roles = @('Admins','Managers','Directors','VPs','Executives','Contractors','Interns','RemoteWorkers')
foreach ($role in $roles) {
    $groupDefs += @{
        Name = "GG-Role-$role"
        Scope = 'Global'
        Desc  = "$role role group"
        Path  = $groupsOU
    }
}

# 5. Resource access groups
$resources = @('VPN-Access','RDP-Access','Admin-Share','HR-Data','Finance-Data','Legal-Data','Dev-Share','Beta-Testers','MFA-Enrolled','BitLocker-Recovery')
foreach ($res in $resources) {
    $groupDefs += @{
        Name = "SG-$res"
        Scope = 'DomainLocal'
        Desc  = "Resource: $res"
        Path  = $groupsOU
    }
}

# Trim or pad to exactly $GroupCount
if ($groupDefs.Count -gt $GroupCount) {
    $groupDefs = $groupDefs[0..($GroupCount - 1)]
} elseif ($groupDefs.Count -lt $GroupCount) {
    $pad = $GroupCount - $groupDefs.Count
    for ($i = 1; $i -le $pad; $i++) {
        $groupDefs += @{ Name = "SG-Custom-$i"; Scope = 'DomainLocal'; Desc = "Custom group $i"; Path = $groupsOU }
    }
}

foreach ($g in $groupDefs) {
    Invoke-Safe {
        if (-not (Get-ADGroup -Filter "Name -eq '$($g.Name)'" -SearchBase $groupsOU -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $g.Name -GroupScope $g.Scope -GroupCategory Security -Path $g.Path -Description $g.Desc -ErrorAction Stop
        }
        $script:created.Groups++
    } "Create group $($g.Name)"
}

Write-Ok "Groups complete: $($created.Groups) created"

# ── Users ─────────────────────────────────────────────────────────────────────

Write-Step "Creating $UserCount users across $($offices.Count) offices and $($departments.Count) departments"

# Distribute users roughly evenly across offices with some variation
$officeWeights = @{ 'HQ-NYC' = 35; 'BRANCH-LAX' = 20; 'BRANCH-CHI' = 18; 'BRANCH-HOU' = 15; 'REMOTE-EU' = 12 }
$totalWeight = ($officeWeights.Values | Measure-Object -Sum).Sum

$usedNames = @{}
$usersPerOffice = @{}

for ($i = 1; $i -le $UserCount; $i++) {

    # Pick office by weight
    $rand = Get-Random -Minimum 1 -Maximum ($totalWeight + 1)
    $cumulative = 0
    $selectedOffice = $offices[0]
    foreach ($office in $offices) {
        $cumulative += $officeWeights[$office.Name]
        if ($rand -le $cumulative) { $selectedOffice = $office; break }
    }

    # Pick random department
    $dept = $departments | Get-Random

    # Pick title from department
    $title = $jobTitles[$dept] | Get-Random

    # Generate unique name
    $first = $firstNames | Get-Random
    $last  = $lastNames  | Get-Random
    $sam   = ($first[0] + $last).ToLower()
    $suffix = 1
    while ($usedNames.ContainsKey($sam)) {
        $sam = "$($first[0].ToLower())$($last.ToLower())$suffix"
        $suffix++
    }
    $usedNames[$sam] = $true

    $fullName = "$first $last"
    $upn      = "$sam@$DomainFQDN"
    $email    = "$sam@$DomainFQDN"
    $deptOU   = $officeDeptOUs["$($selectedOffice.Name)|$dept"]

    # Fallback if OU wasn't created (shouldn't happen, but safety)
    if (-not $deptOU) { $deptOU = $usersOU }

    Invoke-Safe {
        New-ADUser -Name $fullName `
            -GivenName $first -Surname $last `
            -SamAccountName $sam -UserPrincipalName $upn `
            -DisplayName $fullName -Title $title -Department $dept `
            -Company $companyName -EmailAddress $email `
            -StreetAddress $selectedOffice.Street -City $selectedOffice.City `
            -State $selectedOffice.State -PostalCode $selectedOffice.Zip `
            -Country $selectedOffice.Country `
            -Path $deptOU -AccountPassword $securePassword `
            -Enabled $true -ChangePasswordAtLogon $false -ErrorAction Stop

        $script:created.Users++

        # Add to department group for this office
        $deptGroup = "GG-$($selectedOffice.Name)-$dept-Users"
        try { Add-ADGroupMember -Identity $deptGroup -Members $sam -ErrorAction Stop } catch {}

        # Add to office-wide group
        $officeGroup = "GG-$($selectedOffice.Name)-AllStaff"
        try { Add-ADGroupMember -Identity $officeGroup -Members $sam -ErrorAction Stop } catch {}

        # Managers/directors/VPs get role groups
        if ($title -match 'Manager|Team Lead') {
            try { Add-ADGroupMember -Identity 'GG-Role-Managers' -Members $sam -ErrorAction Stop } catch {}
        }
        if ($title -match 'Director') {
            try { Add-ADGroupMember -Identity 'GG-Role-Directors' -Members $sam -ErrorAction Stop } catch {}
        }
        if ($title -match 'VP|CFO|CTO|CMO|COO|CISO') {
            try { Add-ADGroupMember -Identity 'GG-Role-Executives' -Members $sam -ErrorAction Stop } catch {}
        }

        if ($i % 100 -eq 0) {
            Write-Host "    ... $i / $UserCount users created" -ForegroundColor DarkGray
        }
    } "Create user $sam"
}

Write-Ok "Users complete: $($created.Users) created"

# ── Computers ─────────────────────────────────────────────────────────────────

Write-Step "Creating $ComputerCount computers across $($offices.Count) offices"

for ($i = 1; $i -le $ComputerCount; $i++) {
    $compTemplate = $computerPrefixes | Get-Random
    $prefix   = $compTemplate.Prefix
    $os       = $compTemplate.OS
    $compType = $compTemplate.OUType
    $compName = "$prefix-$('{0:D5}' -f $i)"

    # Assign to random office
    $office = $offices | Get-Random
    $targetOU = "OU=$compType,OU=$($office.Name),$computersOU"

    Invoke-Safe {
        if (-not (Get-ADComputer -Filter "Name -eq '$compName'" -ErrorAction SilentlyContinue)) {
            New-ADComputer -Name $compName -SAMAccountName $compName `
                -Path $targetOU -OperatingSystem $os -Enabled $true `
                -AccountPassword $securePassword `
                -Description "$compType - $($office.Name) - $os" `
                -ErrorAction Stop
        }
        $script:created.Computers++

        if ($i % 100 -eq 0) {
            Write-Host "    ... $i / $ComputerCount computers created" -ForegroundColor DarkGray
        }
    } "Create computer $compName"
}

Write-Ok "Computers complete: $($created.Computers) created"

# ── Contacts ──────────────────────────────────────────────────────────────────

Write-Step "Creating 50 mail contacts"

$contactSources = @('gmail.com','yahoo.com','outlook.com','external.com','partner.com','vendor.com','contractor.com')
$createdContacts = @{}
$contactCount = 50

for ($i = 1; $i -le $contactCount; $i++) {
    $first = $firstNames | Get-Random
    $last  = $lastNames  | Get-Random
    $domain = $contactSources | Get-Random
    $email  = "$($first[0].ToLower())$($last.ToLower())@$domain"
    $cname  = "$first $last (External)"

    # Ensure unique
    if ($createdContacts.ContainsKey($cname)) { continue }
    $createdContacts[$cname] = $true

    Invoke-Safe {
        New-ADObject -Type contact -Name $cname -Path $contactsOU `
            -OtherAttributes @{
                mail        = $email
                givenName   = $first
                sn          = $last
                displayName = "$first $last"
            } -ErrorAction Stop
        $script:created.Contacts++
    } "Create contact $cname"
}

Write-Ok "Contacts complete: $($created.Contacts) created"

# ── Service Accounts ──────────────────────────────────────────────────────────

Write-Step "Creating $ServiceAccountCount service accounts"

for ($i = 0; $i -lt $ServiceAccountCount; $i++) {
    $svcName = $svcNames[$i % $svcNames.Count]
    $sam     = "svc-$svcName"

    # Dedupe
    $n = 1
    while (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        $sam = "svc-$($svcName)$n"
        $n++
    }

    Invoke-Safe {
        New-ADUser -Name $sam -SamAccountName $sam -Path $svcOU `
            -DisplayName "$svcName Service Account" -Description "Service account: $svcName" `
            -AccountPassword $securePassword -Enabled $true -PasswordNeverExpires $true `
            -CannotChangePassword $true -ErrorAction Stop
        $script:created.ServiceAccounts++
    } "Create service account $sam"
}

Write-Ok "Service accounts complete: $($created.ServiceAccounts) created"

# ── Domain Admin Accounts ─────────────────────────────────────────────────────

Write-Step "Creating $DomainAdminCount tiered admin accounts"

for ($i = 0; $i -lt [Math]::Min($DomainAdminCount, $adminTiers.Count); $i++) {
    $admin = $adminTiers[$i]
    Invoke-Safe {
        $existing = Get-ADUser -Filter "SamAccountName -eq '$($admin.Name)'" -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-ADUser -Name $admin.Name -SamAccountName $admin.Name -Path $adminOU `
                -DisplayName $admin.Desc -Description $admin.Desc `
                -AccountPassword $securePassword -Enabled $true -PasswordNeverExpires $true `
                -ErrorAction Stop
            Write-Ok "Created admin: $($admin.Name)"

            foreach ($grp in $admin.Groups) {
                try {
                    Add-ADGroupMember -Identity $grp -Members $admin.Name -ErrorAction Stop
                    Write-Ok "  -> Added to $grp"
                } catch {
                    Write-Warn2 "  -> Could not add to $grp (may not exist in lab)"
                }
            }
        }
        $script:created.Admins++
    } "Create admin $($admin.Name)"
}

# If more admins requested than tier definitions, create generic ones
if ($DomainAdminCount -gt $adminTiers.Count) {
    $extra = $DomainAdminCount - $adminTiers.Count
    for ($i = 1; $i -le $extra; $i++) {
        $sam = "adm-custom-$i"
        Invoke-Safe {
            $existing = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
            if (-not $existing) {
                New-ADUser -Name $sam -SamAccountName $sam -Path $adminOU `
                    -DisplayName "Custom Admin $i" -Description "Custom admin account" `
                    -AccountPassword $securePassword -Enabled $true -PasswordNeverExpires $true `
                    -ErrorAction Stop
                try { Add-ADGroupMember -Identity 'Domain Admins' -Members $sam -ErrorAction Stop } catch {}
            }
            $script:created.Admins++
        } "Create custom admin $sam"
    }
}

Write-Ok "Admin accounts complete: $($created.Admins) created"

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor White
Write-Host "  Test AD Population Complete — $DomainFQDN"                    -ForegroundColor Green
Write-Host "  Company: $companyName"                                       -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor White
Write-Host "  OUs created:           $($created.OUs)"                       -ForegroundColor White
Write-Host "  Users created:         $($created.Users)"                    -ForegroundColor White
Write-Host "  Computers created:     $($created.Computers)"                -ForegroundColor White
Write-Host "  Groups created:        $($created.Groups)"                   -ForegroundColor White
Write-Host "  Contacts created:      $($created.Contacts)"                 -ForegroundColor White
Write-Host "  Service accounts:      $($created.ServiceAccounts)"          -ForegroundColor White
Write-Host "  Admin accounts:        $($created.Admins)"                   -ForegroundColor White
Write-Host "  ──────────────────────────────────────────────"              -ForegroundColor White
Write-Host "  Total objects:         $((($created.Values | Measure-Object -Sum).Sum))"               -ForegroundColor Yellow
Write-Host "  Errors:                $($errors.Count)"                     -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor White
Write-Host ""
Write-Host "  Company Structure:"                                          -ForegroundColor Cyan
Write-Host "    Offices: $($offices.Count) — $($offices.Name -join ', ')"  -ForegroundColor White
Write-Host "    Departments: $($departments.Count) — $($departments -join ', ')"  -ForegroundColor White
Write-Host "    Admin tiers: $($adminTiers.Count) (T0 Enterprise, T0 DA, T1 Server, T2 Helpdesk/Desktop)" -ForegroundColor White
Write-Host ""

if ($errors.Count -gt 0) {
    Write-Warn2 "Errors (first 20):"
    $errors | Select-Object -First 20 | ForEach-Object { Write-Err "  $_" }
    Write-Host ""
}

Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "    • Run again with -CleanFirst to wipe and re-seed"
Write-Host "    • Adjust counts: -UserCount, -ComputerCount, -GroupCount, etc."
Write-Host "    • Query counts: (Get-ADUser -Filter * -SearchBase '$rootOU').Count"
Write-Host ""
