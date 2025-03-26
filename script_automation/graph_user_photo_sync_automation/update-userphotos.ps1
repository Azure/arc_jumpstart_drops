# Function to authenticate and retrieve the access token

function Get-AccessToken {
    $invokeRestMethodSplat = @{
        Uri = "https://login.microsoftonline.com/{0}/oauth2/v2.0/token" -f $env:TENANTID
        Method = "POST"
        Headers = @{ "Content-Type" = "application/x-www-form-urlencoded" }
        Body = @{
            client_id = $env:CLIENTID
            client_secret = $env:APP_SECRET
            scope = "https://graph.microsoft.com/.default"
            grant_type = "client_credentials"
        }
    }

    # Retrieve access token
    $access_token = Invoke-RestMethod @invokeRestMethodSplat
    return $access_token.access_token
}


#Get All Users (excluding guests)
$Uri = "https://graph.microsoft.com/beta/users?`$filter=accountEnabled eq true and usertype eq 'Member'&`$select=id,displayName,userPrincipalName,userType,accountEnabled,createdDateTime"

$AccessToken = Get-AccessToken

$Headers = @{
    'Authorization' = 'Bearer ' + $AccessToken
    'Content-Type' = 'application/json'
}

$UsersTable = [ordered]@{}
$RequestUri = $Uri

while ($RequestUri) {
    # Make Graph API call
    $Response = Invoke-RestMethod -Uri $RequestUri -Headers $Headers -Method Get

    # Store users in ordered hash table (prevents duplicates)
    foreach ($User in $Response.value) {
        $UsersTable[$User.id] = $User
    }

    # Check for additional page of results
    $RequestUri = $Response.'@odata.nextLink'

}

Write-Host "Total Users Retrieved: $($UsersTable.Count)"

# Retrieve user photos
$MaxBatchSize = 20 # Graph API limit
$UserIDs = $UsersTable.Keys
$UsersWithPhotos = [ordered]@{}

Write-Host "Fetching user photos in batches of $MaxBatchSize..."

# Process users in chunks of 20
for ($i = 0; $i -lt $UserIDs.Count; $i += $MaxBatchSize) {
    $PhotoBatchRequests = [ordered]@{}
    $BatchRequestID = 0

    # Create a batch of up to 20 users
    foreach ($UserID in $UserIDs[$i..([math]::Min($i + $MaxBatchSize - 1, $UserIDs.Count - 1))]) {
        $BatchRequestID++
        $PhotoBatchRequests["GetPhoto$BatchRequestID"] = @{
            id = "$BatchRequestID"
            method = "GET"
            url = "/users/$UserID/photo"
        }
    }

    # Assemble the batch request
    $PhotoBatchBody = @{
        requests = $PhotoBatchRequests.Values
    } | ConvertTo-Json -Depth 10
    
    $PhotoBatchProperties = @{
        Uri = 'https://graph.microsoft.com/v1.0/$batch'
        Method = 'POST'
        Headers = $Headers
        Body = $PhotoBatchBody
    }

    # Send the batch request
    $PhotoBatchResponse = (Invoke-RestMethod @PhotoBatchProperties).responses

    # Process responses
    foreach ($PhotoResponse in $PhotoBatchResponse) {
        # Extract the batch request ID
        $ResponseID = $PhotoResponse.id
        $RequestedUserID = $UserIDs[$i + [int]$ResponseID - 1] # Map response ID to user ID
        
        if ($PhotoResponse.status -eq 200 -and $PhotoResponse.body.'@odata.mediaContentType') {
            # User has a valid photo
            $UsersWithPhotos[$RequestedUserID] = $true
        } elseif ($PhotoResponse.status -eq 404) {
            Write-Host "No photo found for User ID: $RequestedUserID"
        } else {
            Write-Host "Error fetching photo for User ID: $RequestedUserID - $($PhotoResponse.body.error.message)"
        }
    }

    Write-Host "Processed $BatchRequestID user photos in this batch..."
}

Write-Host "Total Users With Photos: $($UsersWithPhotos.Count)"

# validate that the users reported with a photo is correct
$UsersWithPhotos.Keys | Select-Object -First 20

# validate users without a photo
$UsersTable.Keys | Where-Object { -not $UsersWithPhotos.Contains($_) } | ForEach-Object {
    [PSCustomObject]@{
        UserID = $_
        displayName = $UsersTable[$_].displayName
        Email = $UsersTable[$_].userPrincipalName
        accountEnabled = $UsersTable[$_].accountEnabled
        CreatedDate = $UsersTable[$_].createdDateTime
    }
} | Format-Table -AutoSize

# Patch only users with missing photo
$BasePhotoPath = "/Photos/InProgress/"
$UsersPatched = [ordered]@{}

# Get all photos from folder
$ExistingPhotos = Get-ChildItem -Path $BasePhotoPath -Filter "*.jpg" | Select-Object -ExpandProperty Name

# Find users with missing photos, but have a matching photo in folder
$UsersToPatch = $UsersTable.Keys | Where-Object {
    -not $UsersWithPhotos.Contains($_) -and ("$($UsersTable[$_].displayName).jpg" -in $ExistingPhotos)
}

Write-Host "Total photos available: $($ExistingPhotos.Count)"
Write-Host "Users to be patched: $($UsersToPatch.Count)"

# Find users missing photos and have a matching file in folder

foreach ($UserID in $UsersToPatch) {
    $User = $UsersTable[$UserID]
    $UserPhotoPath = "$BasePhotoPath$($User.displayName).jpg"
    
    if (Test-Path $UserPhotoPath) {
        # Convert photo to Base64
        $PhotoBytes = [System.IO.File]::ReadAllBytes($UserPhotoPath)
        $EncodedPhoto = [Convert]::ToBase64String($PhotoBytes)

        # Create PATCH request
        $PatchBody = $EncodedPhoto | ConvertTo-Json -Depth 10

        $PatchRequestProperties = @{
            Uri = "https://graph.microsoft.com/beta/users/$UserID/photo/`$value"
            Method = "PUT"
            Headers = @{
                'Authorization' = 'Bearer ' + $AccessToken
                'Content-Type' = 'image/jpeg'
            }
            Body = $PhotoBytes
        }
        
        try {
            Invoke-RestMethod @PatchRequestProperties
            Write-Host "Successfully updated photo for $($User.displayName) ($UserID)"
            
            # Store successful patch attempt
            $UsersPatched[$UserID] = [PSCustomObject]@{
                UserID = $UserID
                DisplayName = $User.displayName
                Email = $User.userPrincipalName
                PhotoPath = $UserPhotoPath
            }
        } catch {
            Write-Host "Failed to update photo for $($User.displayName) ($UserID): $_"
        }
    } else {
        Write-Host "Photo not found for $($User.displayName) ($UserID)"
    }
}

Write-Host "Total Users Successfully Patched: $($UsersPatched.Count)"

