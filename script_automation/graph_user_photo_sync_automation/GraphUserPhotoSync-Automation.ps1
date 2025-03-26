# Import required modules
Import-Module Az.Accounts

function log {
    param(
        [string]$Message
    )
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output = "$TimeStamp - $Message"
}

# Connect using Managed Identity
try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    $AccessToken = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com" -ErrorAction Stop
    log "Successfully authenticated using Managed Identity!"
} catch {
    log "Failed to authenticate using Managed Identity: $_" -ErrorAction Stop
    Exit
}

# Define Headers for Graph API requests
$Headers = @{
    "Authorization" = "Bearer $($AccessToken.Token)"
    "Content-Type" = "application/json"
}

log $Headers

# Get All Users (excluding guests)
$Uri = "https://graph.microsoft.com/beta/users?`$filter=accountEnabled eq true and usertype eq 'Member'&`$select=id,displayName,userPrincipalName,userType,accountEnabled,createdDateTime"
$UsersTable = [ordered]@{}
$RequestUri = $Uri

log "Fetching users..."

while ($RequestUri) {
    # Make Graph API call
    $Response = Invoke-RestMethod -Uri $RequestUri -Headers $Headers -Method Get

    # Store users in ordered hash table
    foreach ($User in $Response.value) {
        $UsersTable[$User.id] = $User
    }

    log "Retrieved $($Response.value.Count) users. Total so far: $($UsersTable.Count)"

    # Check for additional page of results
    $RequestUri = $Response.'@odata.nextLink'
}

log "Total Users Retrieved: $($UsersTable.Count)"



$BasePhotoPath = "C:\Photos\InProgress\"
$CompletedPhotoPath = "C:\Photos\Completed\"
$ExistingPhotos = Get-ChildItem -Path $BasePhotoPath -Filter "*.jpg" 

log "Total photos available in directory: $($ExistingPhotos.Count)"

# Convert photo filename to lookup ordered hashtable
$PhotoLookup = [ordered]@{}
foreach ($Photo in $ExistingPhotos) {
    $NamesWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($Photo)
    $PhotoLookup[$NamesWithoutExt] = $Photo.FullName
}



# Patch users that need photos
$UsersToUpdate = [ordered]@{}

foreach ($UserID in $UsersTable.Keys) {
    $User = $UsersTable[$UserId]
    $NormalizedDisplayName = $User.displayName.Trim()
    $PhotoFileName = "$($User.displayName).jpg"

    # If user has a matching photo, queue for update
    if ($PhotoLookup.Contains($NormalizedDisplayName)) {
        $UsersToUpdate[$UserID] = @{
            displayName = $User.displayName
            PhotoPath = $PhotoLookup[$NormalizedDisplayName]
        }
    }
}
log "Users to Update: $($UsersToUpdate.Count)"   

# Upload photos for specified users
$UsersPatched = [ordered]@{}

foreach ($UserID in $UsersToUpdate.Keys) {
    $User = $UsersToUpdate[$UserID]
    $UserPhotoPath = $User.PhotoPath

    if (Test-Path $UserPhotoPath) {
        # Read binary file
        $PhotoBytes = [System.IO.File]::ReadAllBytes($UserPhotoPath)
        log "Binary Data Debugging for $($User.displayName) ($UserID)"
        log "File Size: $($PhotoBytes.Length) bytes"
        log "First 10 Bytest (Hex): $([BitConverter]::ToString($PhotoBytes[0..9]))"

        # Create Patch Request
        $PatchRequestProperties = @{
            Uri = "https://graph.microsoft.com/beta/users/$UserID/photo/`$value"
            Method = "PUT"
            Headers = @{
                "Authorization" = "Bearer $($AccessToken.Token)"
                "Content-Type" = "image/jpeg"
            }
            Body = $PhotoBytes
        }
        
        try {
            Invoke-RestMethod @PatchRequestProperties
            log "Successfully updated photo for $($User.displayName) ($UserID)"

            # Move file to completed folder
            $NewFilePath = "$CompletedPhotoPath$($User.DisplayName).jpg"
            Move-Item -Path $UserPhotoPath -Destination $NewFilePath -Force
            log "Moved photo to Completed Folder: $NewFilePath"

            # Store successful patch attempt
            $UsersPatched[$UserID] = [PSCustomObject]@{
                UserID = $UserID
                DisplayName = $User.displayName
                Email = $User.userPrincipalName
                PhotoPath = $UserPhotoPath
            }
        } catch {
            log "Failed to update photo for $($User.displayName) ($UserID): $_.Exception.Message"
            log "Full API Response: $($_ | ConvertTo-JSON -Depth 10)"
        }
    } else {
    log "Photo not found for $($User.displayName) ($UserID)"
    }
}

log "Total Users Successfully Patched: $($UsersPatched.Count)"