# GraphUserPhotoSync-Automation

## Overview
This script automates **user photo updates** in **Microsoft Entra ID (Azure AD)** using **Microsoft Graph API**.  
It retrieves **all users** first, **stores them in an ordered hash table**, finds **matching photos in a local directory** (such as an **Azure Arc-enabled server**), and updates their profile photos—without requiring the `Microsoft.Graph` PowerShell module.

### Key Benefits
- **Minimizes Graph API calls** to reduce consumption and improve execution speed.
- **Runs in an Azure Automation Account with a Hybrid Worker via Azure Arc**, avoiding cloud sandbox restrictions.
- **Authentication via a Managed Identity** aka no passwords to manage.
- **Processes users efficiently** by handling all retrievals before performing updates.

---

## How It Works

### **1. Retrieves All Users from Microsoft Graph**
- Connects using a **Managed Identity**.
- Queries **all enabled users** (excluding guests).
- Stores user details in an **ordered hash table** for **fast lookups and reduced API calls**.

### **2. Matches Users to Local Photos**
- Reads the **/Photos/InProgress/** directory from a **local server** (such as an Azure Arc-enabled machine).
- Creates a **lookup table of filenames** (`displayName.jpg`).
- Identifies **users who have a matching photo**.

### **3. Uploads Photos to Microsoft Graph**
- Uses **`Invoke-RestMethod`** to efficiently **PATCH profile photos**.
- Sends **raw binary image data** (no base64 encoding required).
- **Minimizes API calls** by only processing users **who actually need an update**.
- Logs **successes and failures** for easy debugging.

### **4. Moves Successfully Processed Photos**
- After a **successful upload**, moves the photo to **/Photos/Completed/**.
- Keeps the `/InProgress/` folder **clean** and **organized**.

---

## Setup & Prerequisites

### **Required Components**
1. **Azure Automation Account**
   - Must be running on a **Hybrid Worker deployed via Azure Arc**.
   - Must use PowerShell 7 in Automation Account.

2. **Managed Identity with Graph API Permissions**
   - Requires:
     - `Directory.Read.All`
     - `User.Read.All` (to fetch user details)
     - `ProfilePhoto.ReadWrite.All` (to update profile photos)

3. **Local Photo Directory**
   - **Source Folder:** `/Photos/InProgress/`
   - **Completed Folder:** `/Photos/Completed/`
   - Filenames **must match user display names** (e.g., `Jane Doe.jpg`).

---

## Deployment Instructions

### **Running the Script in Azure Automation (Hybrid Worker via Azure Arc)**
1. Clone this repository or copy `GraphUserPhotoSync-Automation.ps1`.
2. Upload the script to **Azure Automation Runbooks**.
3. Ensure the **Hybrid Worker is connected via Azure Arc** and has access to Microsoft Graph.
4. Run the script manually or as a **scheduled job**.

---

## Logging & Debugging
This script provides **detailed logs**:
- **Users retrieved from Entra ID** (stored in an ordered hash table).
- **Photos matched to users**.
- **File sizes before upload**.
- **Success and failure messages for uploads**.
- **Full API response errors, if applicable**.

---

## Why Use This Script?
- **Does not require the Microsoft.Graph PowerShell module.**
- **Uses direct `Invoke-RestMethod` calls** for full control.
- **Minimizes Graph API consumption** by efficiently handling users before uploading.
- **Runs on a Hybrid Worker via Azure Arc**, avoiding execution limits.
- **Automatically organizes processed photos**, keeping the directory clean.

---

## Future Enhancements
- Add support for **resizing images** before upload.
- Improve error handling for **invalid filenames** or **missing users**.
- Convert this into a **module** for easier deployment.

---
