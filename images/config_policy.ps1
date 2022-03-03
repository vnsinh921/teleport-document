$Name="Teleport Servier"
$SamAccountName="svc-teleport"
$OutputFile="teleport-svc-pass.txt"

# Generate a random password that meets the "Password must meet complexity requirements" security policy setting.
# Note: if the minimum complexity requirements have been changed from the Windows default, this part of the script may need to be modified.
Add-Type -AssemblyName 'System.Web'
do {
   $Password=[System.Web.Security.Membership]::GeneratePassword(15,1)
} until ($Password -match '\d')
$SecureStringPassword=ConvertTo-SecureString $Password -AsPlainText -Force

# Save the plaintext password to a file for later use in your teleport.yaml.
$Password | Out-File $OutputFile

New-ADUser `
  -Name $Name `
  -SamAccountName $SamAccountName `
  -AccountPassword $SecureStringPassword `
  -Enabled $true

# Save your domain's distinguished name to a variable.
$DomainDN=$((Get-ADDomain).DistinguishedName)

# Create the CDP/Teleport container.
# If the command fails with "New-ADObject : An attempt was made to add an object to the directory with a name that is already in use",
# it means the object already exists and you can move on to the next step.
New-ADObject -Name "Teleport" -Type "container" -Path "CN=CDP,CN=Public Key Services,CN=Services,CN=Configuration,$DomainDN"

# Gives Teleport the ability to create LDAP containers in the CDP container.
dsacls "CN=CDP,CN=Public Key Services,CN=Services,CN=Configuration,$DomainDN" /I:T /G "$($SamAccountName):CC;container;"
# Gives Teleport the ability to create and delete cRLDistributionPoint objects in the CDP/Teleport container.
dsacls "CN=Teleport,CN=CDP,CN=Public Key Services,CN=Services,CN=Configuration,$DomainDN" /I:T /G "$($SamAccountName):CCDC;cRLDistributionPoint;"
# Gives Teleport the ability to write the certificateRevocationList property in the CDP/Teleport container.
dsacls "CN=Teleport,CN=CDP,CN=Public Key Services,CN=Services,CN=Configuration,$DomainDN " /I:T /G "$($SamAccountName):WP;certificateRevocationList;"
# Gives Teleport the ability to create and delete certificationAuthority objects in the NTAuthCertificates container.
dsacls "CN=NTAuthCertificates,CN=Public Key Services,CN=Services,CN=Configuration,$DomainDN" /I:T /G "$($SamAccountName):CCDC;certificationAuthority;"
# Gives Teleport the ability to write the cACertificate property in the NTAuthCertificates container.
dsacls "CN=NTAuthCertificates,CN=Public Key Services,CN=Services,CN=Configuration,$DomainDN" /I:T /G "$($SamAccountName):WP;cACertificate;"

$GPOName="Block teleport-svc Interactive Login"
New-GPO -Name $GPOName | New-GPLink -Target $((Get-ADDomain).DistinguishedName)

$GPOName="Teleport Access Policy"
New-GPO -Name $GPOName | New-GPLink -Target $((Get-ADDomain).DistinguishedName)
gpupdate /force
