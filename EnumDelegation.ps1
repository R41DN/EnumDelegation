# EnumDelegation.ps1
# Autor: Antonio Campodónico Macazana
# Objetivo: Enumerar Unconstrained, Constrained y RBCD usando solo LDAP nativo.
# Funciona en cualquier Windows sin PowerView ni módulos externos.

param(
    [string]$Domain = $null,
    [string]$OutputPath = $null
)

function Get-CurrentDomain {
    try {
        $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
        return $domain
    } catch {
        Write-Warning "No se pudo obtener el dominio actual. Usa -Domain para especificarlo."
        return $null
    }
}

function Format-DelegationOutput {
    param(
        [string]$AccountName,
        [string]$AccountType,
        [string]$DelegationType,
        [string]$DelegationRightsTo,
        [string]$OperatingSystem,
        [string]$Description
    )

    [PSCustomObject]@{
        AccountName = $AccountName
        AccountType = $AccountType
        DelegationType = $DelegationType
        DelegationRightsTo = $DelegationRightsTo
        OperatingSystem = $OperatingSystem
        Description = $Description
    }
}

if (-not $Domain) {
    $Domain = Get-CurrentDomain
    if (-not $Domain) {
        Write-Error "No se pudo determinar el dominio. Especifica uno con -Domain."
        exit 1
    }
}

$ldapPath = "LDAP://$Domain"


try {
    $domainEntry = New-Object System.DirectoryServices.DirectoryEntry($ldapPath)
    $searcher = New-Object System.DirectoryServices.DirectorySearcher($domainEntry)
    $searcher.PageSize = 1000
    $searcher.SearchScope = "Subtree"
} catch {
    Write-Error "No se pudo conectar a LDAP. Verifica permisos y red."
    exit 1
}

$results = @()

Write-Host "[+] Enumerando Unconstrained Delegation..." -ForegroundColor Green

$searcher.Filter = "(&(objectCategory=computer)(userAccountControl:1.2.840.113556.1.4.803:=524288))"
$searcher.PropertiesToLoad.Clear()
$searcher.PropertiesToLoad.AddRange(@("dNSHostName", "operatingSystem", "description", "userAccountControl"))

$unconstrainedComputers = $searcher.FindAll()

foreach ($comp in $unconstrainedComputers) {
    $props = $comp.Properties
    $name = $props["dNSHostName"][0]
    $os = if ($props["operatingSystem"]) { $props["operatingSystem"][0] } else { "N/A" }
    $desc = if ($props["description"]) { $props["description"][0] } else { "N/A" }

    $results += Format-DelegationOutput `
        -AccountName $name `
        -AccountType "Computer" `
        -DelegationType "Unconstrained" `
        -DelegationRightsTo "N/A" `
        -OperatingSystem $os `
        -Description $desc
}

$searcher.Filter = "(&(objectCategory=person)(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=524288))"
$searcher.PropertiesToLoad.Clear()
$searcher.PropertiesToLoad.AddRange(@("sAMAccountName", "displayName", "description", "userAccountControl"))

$unconstrainedUsers = $searcher.FindAll()

foreach ($user in $unconstrainedUsers) {
    $props = $user.Properties
    $name = $props["sAMAccountName"][0]
    $desc = if ($props["description"]) { $props["description"][0] } else { "N/A" }

    $results += Format-DelegationOutput `
        -AccountName $name `
        -AccountType "Person" `
        -DelegationType "Unconstrained" `
        -DelegationRightsTo "N/A" `
        -OperatingSystem "N/A" `
        -Description $desc
}

Write-Host "[+] Enumerando Constrained Delegation..." -ForegroundColor Green

$searcher.Filter = "(&(objectCategory=computer)(msDS-AllowedToDelegateTo=*))" 
$searcher.PropertiesToLoad.Clear()
$searcher.PropertiesToLoad.AddRange(@("dNSHostName", "operatingSystem", "description", "msDS-AllowedToDelegateTo"))

$constrainedComputers = $searcher.FindAll()

foreach ($comp in $constrainedComputers) {
    $props = $comp.Properties
    $name = $props["dNSHostName"][0]
    $os = if ($props["operatingSystem"]) { $props["operatingSystem"][0] } else { "N/A" }
    $desc = if ($props["description"]) { $props["description"][0] } else { "N/A" }
    $services = if ($props["msDS-AllowedToDelegateTo"]) { $props["msDS-AllowedToDelegateTo"] -join "; " } else { "N/A" }

    $results += Format-DelegationOutput `
        -AccountName $name `
        -AccountType "Computer" `
        -DelegationType "Constrained" `
        -DelegationRightsTo $services `
        -OperatingSystem $os `
        -Description $desc
}

$searcher.Filter = "(&(objectCategory=person)(objectClass=user)(msDS-AllowedToDelegateTo=*))" 
$searcher.PropertiesToLoad.Clear()
$searcher.PropertiesToLoad.AddRange(@("sAMAccountName", "displayName", "description", "msDS-AllowedToDelegateTo"))

$constrainedUsers = $searcher.FindAll()

foreach ($user in $constrainedUsers) {
    $props = $user.Properties
    $name = $props["sAMAccountName"][0]
    $desc = if ($props["description"]) { $props["description"][0] } else { "N/A" }
    $services = if ($props["msDS-AllowedToDelegateTo"]) { $props["msDS-AllowedToDelegateTo"] -join "; " } else { "N/A" }

    $results += Format-DelegationOutput `
        -AccountName $name `
        -AccountType "Person" `
        -DelegationType "Constrained" `
        -DelegationRightsTo $services `
        -OperatingSystem "N/A" `
        -Description $desc
}

Write-Host "[+] Enumerando Resource-Based Constrained Delegation (RBCD)..." -ForegroundColor Green

$searcher.Filter = "(msDS-AllowedToActOnBehalfOfOtherIdentity=*)"
$searcher.PropertiesToLoad.Clear()
$searcher.PropertiesToLoad.AddRange(@("name", "dNSHostName", "operatingSystem", "description", "msDS-AllowedToActOnBehalfOfOtherIdentity"))

$rbcdObjects = $searcher.FindAll()

foreach ($obj in $rbcdObjects) {
    $props = $obj.Properties
    $name = if ($props["dNSHostName"]) { $props["dNSHostName"][0] } else { $props["name"][0] }
    $accountType = if ($props["dNSHostName"]) { "Computer" } else { "Person" }
    $os = if ($props["operatingSystem"]) { $props["operatingSystem"][0] } else { "N/A" }
    $desc = if ($props["description"]) { $props["description"][0] } else { "N/A" }
    $services = if ($props["msDS-AllowedToActOnBehalfOfOtherIdentity"]) { $props["msDS-AllowedToActOnBehalfOfOtherIdentity"] -join "; " } else { "N/A" }

    $results += Format-DelegationOutput `
        -AccountName $name `
        -AccountType $accountType `
        -DelegationType "RBCD" `
        -DelegationRightsTo $services `
        -OperatingSystem $os `
        -Description $desc
}

Write-Host "`n[+] Resultados AD:" -ForegroundColor Cyan
$results | Format-Table -AutoSize

if ($OutputPath) {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "[+] Resultados exportados a: $OutputPath" -ForegroundColor Green
}

Write-Host "`n[+] Total objetos encontrados: $($results.Count)" -ForegroundColor Green