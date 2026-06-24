<#
.SYNOPSIS
    Populates a test Active Directory domain with realistic fake objects.

.DESCRIPTION
    Creates OUs, users, computers, groups, contacts, and service accounts
    in a test AD domain. Designed for lab / development environments only.

    Targets the domain specified by -DomainFQDN (default: test.lan).

.PARAMETER DomainFQDN
    The FQDN of the test domain (e.g. test.lan).

.PARAMETER NetBIOS
    NetBIOS name of the domain (e.g. TEST).

.PARAMETER UserCount
    Number of regular user accounts to create (default: 50).

.PARAMETER ComputerCount
    Number of computer accounts to create (default: 30).

.PARAMETER GroupsPerOU
    Number of security groups to create per OU (default: 3).

.PARAMETER ContactCount
    Number of mail contacts to create (default: 10).

.PARAMETER ServiceAccountCount
    Number of service accounts to create (default: 5).

.PARAMETER Password
    Password for all created accounts. Default: TempP@ssw0rd!

.PARAMETER CleanFirst
    If specified, removes the test OUs before creating new objects.

.EXAMPLE
    .\Populate-TestAD.ps1
    Creates 50 users, 30 computers, groups, 10 contacts, 5 service accounts in test.lan.

.EXAMPLE
    .\Populate-TestAD.ps1 -DomainFQDN lab.local -UserCount 200 -CleanFirst
    Creates 200 users in lab.local after cleaning up previous runs.

.NOTES
    Requires: ActiveDirectory PowerShell module
    Run on: Domain-joined machine with RSAT or a Domain Controller
    Permissions: Domain Admin (or account with delegated OU permissions)
#>

[CmdletBinding()]
param(
    [string]$DomainFQDN = 'test.lan',
    [string]$NetBIOS   = 'TEST',
    [int]$UserCount           = 50,
    [int]$ComputerCount       = 30,
    [int]$GroupsPerOU         = 3,
    [int]$ContactCount        = 10,
    [int]$ServiceAccountCount = 5,
    [string]$Password = 'TempP@ssw0rd!',
    [switch]$CleanFirst
)

# ── Bootstrap ────────────────────────────────────────────────────────────────

Import-Module ActiveDirectory -ErrorAction Stop

$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$domainDN = "DC=$(($DomainFQDN -split '\.' ) -join ',DC=')"
$domainNetBIOS = $NetBIOS.ToUpper()

# Data pools for realistic-looking names
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
$departments = @('IT','Finance','HR','Sales','Marketing','Operations','Legal','Engineering','Support','Facilities')
$jobTitles   = @(
    'Analyst','Specialist','Coordinator','Manager','Director','Administrator',
    'Engineer','Technician','Lead','Supervisor','Architect','Consultant'
)
$computerPrefixes = @('WS','LT','VM','SRV','TBL')
$computerOSes     = @(
    'Windows 11 Pro','Windows 10 Pro','Windows 11 Enterprise',
    'Windows Server 2022','Windows Server 2019','Windows 10 Enterprise'
)
$groupPrefixes = @('GG','DL','SG')

# Tracking
$created = @{ Users = 0; Computers = 0; Groups = 0; Contacts = 0; ServiceAccounts = 0; OUs = 0 }
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

function Get-RandomName {
    $first = $firstNames | Get-Random
    $last  = $lastNames  | Get-Random
    return @{
        First   = $first
        Last    = $last
        Full    = "$first $last"
        SamName = ($first[0] + $last).ToLower()
        UPN     = "$($first[0].ToLower()).$($last.ToLower())@$DomainFQDN"
        Email   = "$($first[0].ToLower()).$($last.ToLower())@$DomainFQDN"
    }
}

# ── Clean ─────────────────────────────────────────────────────────────────────

if ($CleanFirst) {
    Write-Step "Cleaning previous test objects under $domainDN ..."

    $testOUs = Get-ADOrganizationalUnit -Filter "Name -like 'Test*'" -SearchBase $domainDN -ErrorAction SilentlyContinue
    foreach ($ou in $testOUs) {
        Invoke-Safe {
            # Remove child objects first
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
        } "Clean OU $($ou.Name)"
    }
}

# ── OUs ───────────────────────────────────────────────────────────────────────

Write-Step "Creating OU structure under $domainDN"

$ouStructure = @(
    @{ Name = 'TestLab';          Path = $domainDN },
    @{ Name = 'Users';            Path = "OU=TestLab,$domainDN" },
    @{ Name = 'Computers';        Path = "OU=TestLab,$domainDN" },
    @{ Name = 'Groups';           Path = "OU=TestLab,$domainDN" },
    @{ Name = 'Contacts';         Path = "OU=TestLab,$domainDN" },
    @{ Name = 'ServiceAccounts';  Path = "OU=TestLab,$domainDN" },
    @{ Name = 'AdminAccounts';    Path = "OU=TestLab,$domainDN" },
    @{ Name = 'Servers';          Path = "OU=Computers,OU=TestLab,$domainDN" },
    @{ Name = 'Workstations';     Path = "OU=Computers,OU=TestLab,$domainDN" }
)

# Also create department OUs under Users
foreach ($dept in $departments) {
    $ouStructure += @{ Name = $dept; Path = "OU=Users,OU=TestLab,$domainDN" }
}

foreach ($ou in $ouStructure) {
    Invoke-Safe {
        $existing = Get-ADOrganizationalUnit -Filter "Name -eq '$($ou.Name)'" -SearchBase $ou.Path -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path -Description "Test lab OU: $($ou.Name)" -ErrorAction Stop
            Write-Ok "Created OU: $($ou.Name)"
        }
        $script:created.OUs++
    } "Create OU $($ou.Name)"
}

# Resolve OU DNs
$usersOU         = "OU=Users,OU=TestLab,$domainDN"
$computersOU     = "OU=Computers,OU=TestLab,$domainDN"
$groupsOU        = "OU=Groups,OU=TestLab,$domainDN"
$contactsOU      = "OU=Contacts,OU=TestLab,$domainDN"
$svcAccountsOU   = "OU=ServiceAccounts,OU=TestLab,$domainDN"
$adminAccountsOU = "OU=AdminAccounts,OU=TestLab,$domainDN"
$serversOU       = "OU=Servers,OU=Computers,OU=TestLab,$domainDN"
$workstationsOU  = "OU=Workstations,OU=Computers,OU=TestLab,$domainDN"

# ── Groups ────────────────────────────────────────────────────────────────────

Write-Step "Creating security groups"

$groupNames = @()
for ($i = 1; $i -le $GroupsPerOU; $i++) {
    foreach ($prefix in $groupPrefixes) {
        $groupNames += "$prefix-Test-$i"
    }
}

# Department-based groups
foreach ($dept in $departments) {
    $groupNames += "GG-$dept-Users"
}

foreach ($gname in $groupNames) {
    Invoke-Safe {
        $existing = Get-ADGroup -Filter "Name -eq '$gname'" -SearchBase $groupsOU -ErrorAction SilentlyContinue
        if (-not $existing) {
            $scope = if ($gname.StartsWith('DL')) { 'DomainLocal' } elseif ($gname.StartsWith('SG')) { 'Global' } else { 'Global' }
            New-ADGroup -Name $gname -GroupScope $scope -GroupCategory Security -Path $groupsOU -Description "Test group: $gname" -ErrorAction Stop
            Write-Ok "Created group: $gname"
        }
        $script:created.Groups++
    } "Create group $gname"
}

# ── Users ─────────────────────────────────────────────────────────────────────

Write-Step "Creating $UserCount user accounts"

$createdUsers = @()

for ($i = 1; $i -le $UserCount; $i++) {
    $nameInfo = Get-RandomName
    $dept     = $departments | Get-Random
    $title    = $jobTitles   | Get-Random
    $deptOU   = "OU=$dept,$usersOU"

    # Ensure samAccountName is unique
    $sam    = $nameInfo.SamName
    $suffix = 1
    while (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        $sam = "$($nameInfo.SamName)$suffix"
        $suffix++
    }

    Invoke-Safe {
        $newUserParams = @{
            Name              = $nameInfo.Full
            GivenName         = $nameInfo.First
            Surname           = $nameInfo.Last
            SamAccountName    = $sam
            UserPrincipalName = $sam + "@$DomainFQDN"
            DisplayName       = $nameInfo.Full
            Title             = $title
            Department        = $dept
            EmailAddress      = $nameInfo.Email
            Company           = 'Test Corp'
            Path              = $deptOU
            AccountPassword   = $securePassword
            Enabled           = $true
            ChangePasswordAtLogon = $false
            ErrorAction       = 'Stop'
        }
        New-ADUser @newUserParams
        Write-Ok "Created user: $sam ($($nameInfo.Full))"

        # Add to department group
        $deptGroup = "GG-$dept-Users"
        try {
            Add-ADGroupMember -Identity $deptGroup -Members $sam -ErrorAction Stop
        } catch {
            # Group might not exist yet in this run — skip silently
        }

        $script:created.Users++
        $script:createdUsers += $sam
    } "Create user $sam"
}

# ── Computers ─────────────────────────────────────────────────────────────────

Write-Step "Creating $ComputerCount computer accounts"

for ($i = 1; $i -le $ComputerCount; $i++) {
    $prefix    = $computerPrefixes | Get-Random
    $os        = $computerOSes     | Get-Random
    $compName  = "$prefix-$('{0:D4}' -f $i)"
    $targetOU  = if ($prefix -eq 'SRV' -or $prefix -eq 'VM') { $serversOU } else { $workstationsOU }

    Invoke-Safe {
        $existing = Get-ADComputer -Filter "Name -eq '$compName'" -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-ADComputer -Name $compName -SAMAccountName $compName -Path $targetOU `
                -OperatingSystem $os -Enabled $true -AccountPassword $securePassword `
                -Description "Test computer: $compName ($os)" -ErrorAction Stop
            Write-Ok "Created computer: $compName ($os)"
        }
        $script:created.Computers++
    } "Create computer $compName"
}

# ── Contacts ──────────────────────────────────────────────────────────────────

Write-Step "Creating $ContactCount mail contacts"

$contactSources = @('gmail.com','yahoo.com','outlook.com','hotmail.com','external.com','partner.com')

for ($i = 1; $i -le $ContactCount; $i++) {
    $nameInfo = Get-RandomName
    $domain   = $contactSources | Get-Random
    $email    = "$($nameInfo.SamName)@$domain"
    $cname    = "$($nameInfo.Full) (External)"

    Invoke-Safe {
        New-ADObject -Type contact -Name $cname -Path $contactsOU `
            -OtherAttributes @{
                mail        = $email
                givenName   = $nameInfo.First
                sn          = $nameInfo.Last
                displayName = $nameInfo.Full
            } -ErrorAction Stop
        Write-Ok "Created contact: $cname ($email)"
        $script:created.Contacts++
    } "Create contact $cname"
}

# ── Service Accounts ──────────────────────────────────────────────────────────

Write-Step "Creating $ServiceAccountCount service accounts"

$svcNames = @('sql-svc','web-svc','backup-svc','sync-svc','report-svc','adconnect-svc','papercut-svc','snipeit-svc')

for ($i = 0; $i -lt $ServiceAccountCount; $i++) {
    $svcName = $svcNames[$i % $svcNames.Count]
    $sam     = "svc-$svcName"

    # Avoid duplicates
    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        $sam = "$svcName$('{0:D2}' -f ($i + 1))"
    }

    Invoke-Safe {
        New-ADUser -Name $sam -SamAccountName $sam -Path $svcAccountsOU `
            -DisplayName "$svcName Service Account" -Description "Service account: $svcName" `
            -AccountPassword $securePassword -Enabled $true -PasswordNeverExpires $true `
            -CannotChangePassword $true -ErrorAction Stop
        Write-Ok "Created service account: $sam"
        $script:created.ServiceAccounts++
    } "Create service account $sam"
}

# ── Admin Accounts ────────────────────────────────────────────────────────────

Write-Step "Creating tiered admin accounts"

$adminTiers = @(
    @{ Name = 'adm-t0-da';     Desc = 'Tier-0 Domain Admin';       Groups = @('Domain Admins') }
    @{ Name = 'adm-t1-server';  Desc = 'Tier-1 Server Admin';      Groups = @('Server Operators') }
    @{ Name = 'adm-t2-helpdesk';Desc = 'Tier-2 Helpdesk';          Groups = @('Account Operators') }
)

foreach ($admin in $adminTiers) {
    Invoke-Safe {
        $existing = Get-ADUser -Filter "SamAccountName -eq '$($admin.Name)'" -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-ADUser -Name $admin.Name -SamAccountName $admin.Name -Path $adminAccountsOU `
                -DisplayName $admin.Desc -Description $admin.Desc `
                -AccountPassword $securePassword -Enabled $true -PasswordNeverExpires $true `
                -ErrorAction Stop
            Write-Ok "Created admin account: $($admin.Name)"

            foreach ($grp in $admin.Groups) {
                try {
                    Add-ADGroupMember -Identity $grp -Members $admin.Name -ErrorAction Stop
                    Write-Ok "  -> Added $($admin.Name) to $grp"
                } catch {
                    Write-Warn2 "  -> Could not add $($admin.Name) to $grp (may not exist in lab)"
                }
            }
        }
    } "Create admin $($admin.Name)"
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor White
Write-Host "  Test AD Population Complete — $DomainFQDN"                -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor White
Write-Host "  OUs created:           $($created.OUs)"                    -ForegroundColor White
Write-Host "  Users created:         $($created.Users)"                 -ForegroundColor White
Write-Host "  Computers created:     $($created.Computers)"             -ForegroundColor White
Write-Host "  Groups created:        $($created.Groups)"                -ForegroundColor White
Write-Host "  Contacts created:      $($created.Contacts)"              -ForegroundColor White
Write-Host "  Service accounts:      $($created.ServiceAccounts)"       -ForegroundColor White
Write-Host "  Admin accounts:        3 (Tier-0/1/2)"                   -ForegroundColor White
Write-Host "  Errors encountered:    $($errors.Count)"                 -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor White

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Warn2 "Errors (first 10):"
    $errors | Select-Object -First 10 | ForEach-Object { Write-Err "  $_" }
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  • Run Invoke-TestADQueries.ps1 to verify object counts"
Write-Host "  • Use -CleanFirst to wipe and re-seed"
Write-Host "  • Adjust counts with -UserCount, -ComputerCount, etc."
Write-Host ""
