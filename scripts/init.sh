#!/bin/bash

# infra-seed Infrastructure Initialization Script
# This script sets up everything needed to deploy the infrastructure

set -e  # Exit on error

# Initialize log file
LOG_FILE="init.log"
echo "# infra-seed Infrastructure Initialization Log" > "$LOG_FILE"
echo "# Generated: $(date)" >> "$LOG_FILE"
echo "# This file contains all commands executed during initialization" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to log commands
log_command() {
    local cmd="$1"
    echo "# $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "$cmd" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

# Function to read password with asterisks
read_password() {
    local password=""
    local char
    
    # Disable terminal echo for actual characters
    stty -echo
    
    while IFS= read -r -n1 char; do
        # Check for Enter key (empty char after newline)
        if [[ -z "$char" ]]; then
            break
        fi
        
        # Check for backspace (ASCII 127 or ^H)
        if [[ "$char" == $'\177' || "$char" == $'\b' ]]; then
            if [ ${#password} -gt 0 ]; then
                password="${password%?}"
                # Move cursor back, print space to erase asterisk, move back again
                printf '\b \b' >&2
            fi
        else
            # Add character to password
            password+="$char"
            # Print asterisk to stderr so it's not captured by command substitution
            printf '*' >&2
        fi
    done
    
    # Re-enable terminal echo
    stty echo
    # New line after password entry to stderr
    echo >&2
    
    # Return ONLY the password to stdout
    echo "$password"
}

# Function to execute commands with confirmation
run_command() {
    local cmd="$1"
    local description="$2"
    
    while true; do
        echo ""
        if [ -n "$description" ]; then
            echo -e "${CYAN}$description${NC}"
        fi
        echo -e "${YELLOW}Command:${NC} $cmd"
        read -p "Execute this command? (y/exit) " REPLY
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_command "$cmd"
            eval "$cmd"
            return $?
        elif [[ $REPLY == "exit" ]]; then
            echo -e "${RED}Setup cancelled by user${NC}"
            exit 1
        else
            echo -e "${RED}Invalid input. Please enter 'y' to execute or 'exit' to cancel setup.${NC}"
        fi
    done
}

# Function to check if Cloudflare API token exists in Secret Manager
check_cloudflare_token() {
    local project_id="$1"
    
    # Check if Secret Manager API is enabled first
    local sm_enabled=$(gcloud services list --filter="name:secretmanager.googleapis.com AND state:ENABLED" --format="value(name)" --project="$project_id" 2>/dev/null)
    
    if [ -z "$sm_enabled" ]; then
        return 1  # Secret Manager API not enabled
    fi
    
    # Check if the secret exists
    local secret_exists=$(gcloud secrets list --filter="name:cloudflare-api-token" --format="value(name)" --project="$project_id" 2>/dev/null)
    
    if [ -n "$secret_exists" ]; then
        # Check if the secret has any versions
        local latest_version=$(gcloud secrets versions list cloudflare-api-token --limit=1 --filter="state:ENABLED" --format="value(name)" --project="$project_id" 2>/dev/null)
        
        if [ -n "$latest_version" ]; then
            return 0  # Secret exists and has valid versions
        fi
    fi
    
    return 1  # Secret doesn't exist or has no valid versions
}

echo "=========================================="
echo "infra-seed Infrastructure Initialization"
echo "=========================================="
echo ""

# Prerequisites Check
echo -e "${BLUE}Prerequisites Check${NC}"
echo ""

MISSING_TOOLS=()
OPTIONAL_TOOLS=()

# Check required tools
echo "Checking required tools..."

if ! command -v gcloud &> /dev/null; then
    MISSING_TOOLS+=("gcloud")
    echo -e "${RED}✗ gcloud CLI not found${NC}"
else
    GCLOUD_VERSION=$(gcloud version --format="value(core)" 2>/dev/null || gcloud version 2>/dev/null | head -n1 | awk '{print $4}')
    echo -e "${GREEN}✓ gcloud CLI installed${NC} (${GCLOUD_VERSION})"
fi

if ! command -v terraform &> /dev/null; then
    MISSING_TOOLS+=("terraform")
    echo -e "${RED}✗ terraform not found${NC}"
else
    TERRAFORM_VERSION=$(terraform version 2>/dev/null | head -n1 | sed 's/Terraform v//' | awk '{print $1}')
    echo -e "${GREEN}✓ terraform installed${NC} (${TERRAFORM_VERSION})"
fi

if ! command -v gsutil &> /dev/null; then
    MISSING_TOOLS+=("gsutil")
    echo -e "${RED}✗ gsutil not found${NC}"
else
    GSUTIL_VERSION=$(gsutil version -l 2>/dev/null | head -n1 | awk '{print $3}')
    echo -e "${GREEN}✓ gsutil installed${NC} (${GSUTIL_VERSION})"
fi

if ! command -v kubectl &> /dev/null; then
    MISSING_TOOLS+=("kubectl")
    echo -e "${RED}✗ kubectl not found${NC}"
else
    KUBECTL_VERSION=$(kubectl version --client 2>/dev/null | grep -o 'v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' | head -n1)
    echo -e "${GREEN}✓ kubectl installed${NC} (${KUBECTL_VERSION})"
fi

# Check optional tools
echo ""
echo "Checking optional tools..."

if ! command -v gh &> /dev/null; then
    OPTIONAL_TOOLS+=("gh")
    echo -e "${YELLOW}⚠ gh CLI not found (optional, but recommended for GitHub automation)${NC}"
else
    GH_VERSION=$(gh --version 2>/dev/null | head -n1 | awk '{print $3}')
    echo -e "${GREEN}✓ gh CLI installed${NC} (${GH_VERSION})"
fi

if ! command -v curl &> /dev/null; then
    OPTIONAL_TOOLS+=("curl")
    echo -e "${YELLOW}⚠ curl not found (optional, used for API checks)${NC}"
else
    CURL_VERSION=$(curl --version 2>/dev/null | head -n1 | awk '{print $2}')
    echo -e "${GREEN}✓ curl installed${NC} (${CURL_VERSION})"
fi

# Report missing required tools
if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}================================${NC}"
    echo -e "${RED}Missing Required Tools${NC}"
    echo -e "${RED}================================${NC}"
    echo ""
    echo "The following required tools are missing:"
    for tool in "${MISSING_TOOLS[@]}"; do
        echo "  - $tool"
    done
    echo ""
    echo "Installation instructions:"
    echo ""
    
    if [[ " ${MISSING_TOOLS[@]} " =~ " gcloud " ]]; then
        echo -e "${CYAN}gcloud CLI:${NC}"
        echo "  macOS:   https://cloud.google.com/sdk/docs/install#mac"
        echo "  Linux:   https://cloud.google.com/sdk/docs/install#linux"
        echo "  Windows: https://cloud.google.com/sdk/docs/install#windows"
        echo ""
    fi
    
    if [[ " ${MISSING_TOOLS[@]} " =~ " terraform " ]]; then
        echo -e "${CYAN}Terraform:${NC}"
        echo "  macOS:   brew install terraform"
        echo "  Linux:   https://developer.hashicorp.com/terraform/install"
        echo "  Windows: https://developer.hashicorp.com/terraform/install"
        echo ""
    fi
    
    if [[ " ${MISSING_TOOLS[@]} " =~ " gsutil " ]]; then
        echo -e "${CYAN}gsutil:${NC}"
        echo "  Installed as part of gcloud SDK"
        echo "  If gcloud is installed, run: gcloud components install gsutil"
        echo ""
    fi
    
    if [[ " ${MISSING_TOOLS[@]} " =~ " kubectl " ]]; then
        echo -e "${CYAN}kubectl:${NC}"
        echo "  macOS:   brew install kubectl"
        echo "           or: gcloud components install kubectl"
        echo "  Linux:   https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
        echo "           or: gcloud components install kubectl"
        echo "  Windows: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/"
        echo "           or: gcloud components install kubectl"
        echo ""
    fi
    
    echo "Please install the missing tools and run this script again."
    exit 1
fi

# Report optional tools
if [ ${#OPTIONAL_TOOLS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}================================${NC}"
    echo -e "${YELLOW}Optional Tools${NC}"
    echo -e "${YELLOW}================================${NC}"
    echo ""
    echo "The following optional tools are not installed:"
    for tool in "${OPTIONAL_TOOLS[@]}"; do
        echo "  - $tool"
    done
    echo ""
    echo "Installation instructions:"
    echo ""
    
    if [[ " ${OPTIONAL_TOOLS[@]} " =~ " gh " ]]; then
        echo -e "${CYAN}GitHub CLI (gh):${NC}"
        echo "  macOS:   brew install gh"
        echo "  Linux:   https://github.com/cli/cli#installation"
        echo "  Windows: https://github.com/cli/cli#installation"
        echo "  Note: Required for GitHub automation features"
        echo ""
    fi
    
    if [[ " ${OPTIONAL_TOOLS[@]} " =~ " curl " ]]; then
        echo -e "${CYAN}curl:${NC}"
        echo "  macOS:   (usually pre-installed)"
        echo "  Linux:   sudo apt-get install curl (Debian/Ubuntu)"
        echo "           sudo yum install curl (RHEL/CentOS)"
        echo ""
    fi
    
    read -p "Continue without optional tools? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup cancelled. Install the optional tools and run this script again."
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}✓ All required tools are installed${NC}"
echo ""

# Step 1: Authenticate with Google Cloud
echo -e "${BLUE}Step 1: Google Cloud Authentication${NC}"
echo ""

# Check if already authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
    echo "You need to authenticate with Google Cloud"
    run_command "gcloud auth login" "Authenticate with Google Cloud"
else
    CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    echo -e "Already authenticated as: ${GREEN}${CURRENT_ACCOUNT}${NC}"
fi

echo ""

# Step 2: GCP Project Setup
echo -e "${BLUE}Step 2: GCP Project Setup${NC}"
echo ""

# Check if project already exists
EXISTING_PROJECT=$(gcloud config get-value project 2>/dev/null)

if [ -n "$EXISTING_PROJECT" ]; then
    # Check if the existing project is active
    PROJECT_STATE=$(gcloud projects describe $EXISTING_PROJECT --format="value(lifecycleState)" 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$PROJECT_STATE" = "ACTIVE" ]; then
        echo -e "Current project: ${GREEN}${EXISTING_PROJECT}${NC} (Active)"
        echo ""
        echo "What would you like to do?"
        echo "  1) Use this project"
        echo "  2) Use a different existing project"
        echo "  3) Create a new project"
        read -p "Enter choice (1-3): " CHOICE
        
        if [ "$CHOICE" = "1" ]; then
            PROJECT_ID=$EXISTING_PROJECT
        elif [ "$CHOICE" = "2" ] || [ "$CHOICE" = "3" ]; then
            read -p "Enter project ID: " PROJECT_ID
            while [ -z "$PROJECT_ID" ]; do
                echo -e "${RED}Project ID is required${NC}"
                read -p "Enter project ID: " PROJECT_ID
            done
            
            # Check if project exists
            PROJECT_STATE=$(gcloud projects describe $PROJECT_ID --format="value(lifecycleState)" 2>/dev/null || echo "NOT_FOUND")
            
            if [ "$PROJECT_STATE" = "ACTIVE" ]; then
                echo -e "${GREEN}Project $PROJECT_ID exists and is active${NC}"
            elif [ "$PROJECT_STATE" = "DELETE_REQUESTED" ]; then
                echo -e "${RED}Error: Project $PROJECT_ID is pending deletion${NC}"
                echo "Cannot use this project. Please choose a different project ID."
                exit 1
            elif [ "$PROJECT_STATE" = "NOT_FOUND" ]; then
                if [ "$CHOICE" = "2" ]; then
                    echo -e "${RED}Error: Project $PROJECT_ID does not exist${NC}"
                    echo "You selected 'use existing' but the project was not found."
                    exit 1
                else
                    # Choice 3: Create new
                    if run_command "gcloud projects create $PROJECT_ID --name='$PROJECT_ID'" "Create new GCP project"; then
                        echo -e "${GREEN}✓ Project created${NC}"
                    else
                        echo -e "${RED}Failed to create project${NC}"
                        exit 1
                    fi
                fi
            else
                echo -e "${YELLOW}Warning: Project is in state: $PROJECT_STATE${NC}"
                read -p "Continue with this project? (y/n) " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            fi
        else
            echo -e "${RED}Invalid choice${NC}"
            exit 1
        fi
    elif [ "$PROJECT_STATE" = "DELETE_REQUESTED" ]; then
        echo -e "${RED}Warning: Current project ${EXISTING_PROJECT} is pending deletion${NC}"
        echo "You must choose a different project"
        read -p "Enter new project ID (e.g., infra-seed-prod-123): " PROJECT_ID
        while [ -z "$PROJECT_ID" ]; do
            echo -e "${RED}Project ID is required${NC}"
            read -p "Enter project ID: " PROJECT_ID
        done
        
        # Check new project state
        NEW_PROJECT_STATE=$(gcloud projects describe $PROJECT_ID --format="value(lifecycleState)" 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$NEW_PROJECT_STATE" = "ACTIVE" ]; then
            echo -e "${GREEN}Project exists and is active${NC}"
        elif [ "$NEW_PROJECT_STATE" = "DELETE_REQUESTED" ]; then
            echo -e "${RED}Error: Project $PROJECT_ID is also pending deletion${NC}"
            echo "Please choose a different project ID"
            exit 1
        elif [ "$NEW_PROJECT_STATE" = "NOT_FOUND" ]; then
            if run_command "gcloud projects create $PROJECT_ID --name='$PROJECT_ID'" "Create new GCP project"; then
                echo -e "${GREEN}✓ Project created${NC}"
            else
                echo -e "${RED}Failed to create project${NC}"
                exit 1
            fi
        fi
    else
        echo -e "${YELLOW}Warning: Current project is in state: $PROJECT_STATE${NC}"
        read -p "Enter new project ID (e.g., infra-seed-prod-123): " PROJECT_ID
        while [ -z "$PROJECT_ID" ]; do
            echo -e "${RED}Project ID is required${NC}"
            read -p "Enter project ID: " PROJECT_ID
        done
        
        if run_command "gcloud projects create $PROJECT_ID --name='$PROJECT_ID'" "Create new GCP project"; then
            echo -e "${GREEN}✓ Project created${NC}"
        else
            echo -e "${RED}Failed to create project${NC}"
            exit 1
        fi
    fi
else
    # No project set, create new one
    read -p "Enter project ID (e.g., infra-seed-prod-123): " PROJECT_ID
    while [ -z "$PROJECT_ID" ]; do
        echo -e "${RED}Project ID is required${NC}"
        read -p "Enter project ID: " PROJECT_ID
    done
    
    # Check if project exists and its state
    PROJECT_STATE=$(gcloud projects describe $PROJECT_ID --format="value(lifecycleState)" 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$PROJECT_STATE" = "ACTIVE" ]; then
        echo -e "${GREEN}Project exists and is active${NC}"
    elif [ "$PROJECT_STATE" = "DELETE_REQUESTED" ]; then
        echo -e "${RED}Error: Project $PROJECT_ID is pending deletion${NC}"
        echo "You cannot use this project ID until it's permanently deleted (30 days)"
        echo "Please choose a different project ID or wait for deletion to complete"
        exit 1
    elif [ "$PROJECT_STATE" = "NOT_FOUND" ]; then
        if run_command "gcloud projects create $PROJECT_ID --name='$PROJECT_ID'" "Create new GCP project"; then
            echo -e "${GREEN}✓ Project created${NC}"
        else
            echo -e "${RED}Failed to create project${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}Warning: Project is in state: $PROJECT_STATE${NC}"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# Set as default project
echo ""
if run_command "gcloud config set project $PROJECT_ID" "Set $PROJECT_ID as default project"; then
    echo -e "${GREEN}✓ Project configured${NC}"
    
    # Set quota project to avoid warnings
    if run_command "gcloud auth application-default set-quota-project $PROJECT_ID" "Set quota project for Application Default Credentials"; then
        echo -e "${GREEN}✓ Quota project configured${NC}"
    fi
fi

# Enable billing (required)
echo ""
echo -e "${BLUE}Step 3: Billing Setup (Required)${NC}"
echo ""
echo -e "${YELLOW}Billing Setup:${NC}"
echo "GCP services require an active billing account to be linked to the project."
echo ""

BILLING_LINKED=false
while [ "$BILLING_LINKED" = false ]; do
    echo "Available billing accounts:"
    
    # Create a temporary file to store billing account info
    TEMP_BILLING_FILE=$(mktemp)
    gcloud billing accounts list --format="csv[no-heading](name,displayName)" 2>/dev/null > "$TEMP_BILLING_FILE"
    
    # Check if we have any billing accounts
    if [ ! -s "$TEMP_BILLING_FILE" ]; then
        echo -e "${RED}No billing accounts found${NC}"
        echo "Please ensure you have billing.accounts.list permission or create a billing account first."
        rm -f "$TEMP_BILLING_FILE"
        exit 1
    fi
    
    # Extract just the account IDs for the array
    BILLING_ACCOUNTS=($(gcloud billing accounts list --format="value(name)" 2>/dev/null | grep -o '[A-Z0-9]\{6\}-[A-Z0-9]\{6\}-[A-Z0-9]\{6\}'))
    
    # Display numbered list using the CSV data
    counter=1
    while IFS=',' read -r account_name display_name; do
        # Extract just the billing account ID from the full name
        account_id=$(echo "$account_name" | grep -o '[A-Z0-9]\{6\}-[A-Z0-9]\{6\}-[A-Z0-9]\{6\}')
        # Remove quotes from display name if present
        display_name=$(echo "$display_name" | sed 's/^"//; s/"$//')
        echo "  $counter) $account_id - $display_name"
        ((counter++))
    done < "$TEMP_BILLING_FILE"
    rm -f "$TEMP_BILLING_FILE"
    echo ""
    
    read -p "Select billing account (1-${#BILLING_ACCOUNTS[@]}) or 'exit' to quit: " SELECTION
    
    if [ "$SELECTION" = "exit" ]; then
        echo -e "${RED}Setup cancelled - billing account is required${NC}"
        exit 1
    fi
    
    # Validate selection is a number
    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Please enter a valid number (1-${#BILLING_ACCOUNTS[@]})${NC}"
        echo ""
        continue
    fi
    
    # Validate selection is within range
    if [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt ${#BILLING_ACCOUNTS[@]} ]; then
        echo -e "${RED}Please enter a number between 1 and ${#BILLING_ACCOUNTS[@]}${NC}"
        echo ""
        continue
    fi
    
    # Get the selected billing account
    BILLING_ACCOUNT=${BILLING_ACCOUNTS[$((SELECTION-1))]}
    
    if run_command "gcloud billing projects link $PROJECT_ID --billing-account=$BILLING_ACCOUNT" "Link billing account to project"; then
        echo -e "${GREEN}✓ Billing account linked${NC}"
        BILLING_LINKED=true
    else
        echo -e "${RED}Failed to link billing account${NC}"
        echo "This may be due to:"
        echo "  - Insufficient permissions"
        echo "  - Billing account is disabled"
        echo "  - Project already has billing"
        echo ""
        read -p "Try again? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${RED}Setup cancelled - billing account is required${NC}"
            exit 1
        fi
    fi
done

echo ""

# Step 4: Cloudflare API Token (Required)
echo -e "${BLUE}Step 4: Cloudflare API Token (Required)${NC}"
echo ""

# Enable Secret Manager API first
if run_command "gcloud services enable secretmanager.googleapis.com" "Enable Secret Manager API"; then
    echo -e "${GREEN}✓ Secret Manager API enabled${NC}"
fi

echo ""

# Check if Cloudflare API token already exists in Secret Manager
if check_cloudflare_token "$PROJECT_ID"; then
    echo -e "${GREEN}✓ Cloudflare API token already exists in Secret Manager for project: ${PROJECT_ID}${NC}"
    echo ""
    echo "What would you like to do?"
    echo "  1) Use the existing token"
    echo "  2) Update with a new token"
    read -p "Enter choice (1-2): " TOKEN_CHOICE
    
    if [ "$TOKEN_CHOICE" = "1" ]; then
        echo -e "${GREEN}✓ Using existing Cloudflare API token${NC}"
        TOKEN_STORED=true
    elif [ "$TOKEN_CHOICE" = "2" ]; then
        echo ""
        echo "You need a Cloudflare API token with the following permissions:"
        echo "  - Zone:Zone Settings:Edit"
        echo "  - Zone:Zone:Read"  
        echo "  - Zone:DNS:Edit"
        echo "  - Zone:Page Rules:Edit"
        echo ""
        echo "Create one at: https://dash.cloudflare.com/profile/api-tokens"
        echo ""
        read -p "Press Enter when you have your new token ready..."
        TOKEN_STORED=false
    else
        echo -e "${RED}Invalid choice. Using existing token.${NC}"
        TOKEN_STORED=true
    fi
else
    echo "No Cloudflare API token found in Secret Manager for project: ${PROJECT_ID}"
    echo ""
    echo "You need a Cloudflare API token with the following permissions:"
    echo "  - Zone:Zone Settings:Edit"
    echo "  - Zone:Zone:Read"  
    echo "  - Zone:DNS:Edit"
    echo "  - Zone:Page Rules:Edit"
    echo ""
    echo "Create one at: https://dash.cloudflare.com/profile/api-tokens"
    echo ""
    read -p "Press Enter when you have your token ready..."
    TOKEN_STORED=false
fi

# Store Cloudflare token (only if needed)
while [ "$TOKEN_STORED" = false ]; do
    echo ""
    echo "Enter your Cloudflare API token (input will show as asterisks):"
    CLOUDFLARE_TOKEN=$(read_password)
    
    if [ -z "$CLOUDFLARE_TOKEN" ]; then
        echo -e "${RED}Token is required${NC}"
        continue
    fi
    
    # Check if secret already exists
    SECRET_EXISTS=$(gcloud secrets list --filter="name:cloudflare-api-token" --format="value(name)" 2>/dev/null)
    
    echo ""
    if [ -n "$SECRET_EXISTS" ]; then
        echo "Updating existing token in Secret Manager (creating new version)..."
        log_command "echo -n \"\$CLOUDFLARE_TOKEN\" | gcloud secrets versions add cloudflare-api-token --data-file=-"
        if echo -n "$CLOUDFLARE_TOKEN" | gcloud secrets versions add cloudflare-api-token --data-file=- 2>/dev/null; then
            unset CLOUDFLARE_TOKEN
            echo -e "${GREEN}✓ Token updated (new version created)${NC}"
            TOKEN_STORED=true
        else
            unset CLOUDFLARE_TOKEN
            echo -e "${RED}Failed to update token${NC}"
            echo ""
            read -p "Try again? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${RED}Setup cancelled - Cloudflare token is required${NC}"
                exit 1
            fi
        fi
    else
        echo "Creating new secret in Secret Manager..."
        log_command "echo -n \"\$CLOUDFLARE_TOKEN\" | gcloud secrets create cloudflare-api-token --data-file=- --replication-policy=\"automatic\""
        if echo -n "$CLOUDFLARE_TOKEN" | gcloud secrets create cloudflare-api-token \
          --data-file=- \
          --replication-policy="automatic" 2>/dev/null; then
            unset CLOUDFLARE_TOKEN
            echo -e "${GREEN}✓ Token stored securely${NC}"
            TOKEN_STORED=true
        else
            unset CLOUDFLARE_TOKEN
            echo -e "${RED}Failed to create secret${NC}"
            echo ""
            read -p "Try again? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${RED}Setup cancelled - Cloudflare token is required${NC}"
                exit 1
            fi
        fi
    fi
done

echo ""

# Step 5: Terraform Backend Setup
echo -e "${BLUE}Step 5: Terraform Backend Setup${NC}"
echo ""

BUCKET_NAME="${PROJECT_ID}-terraform-state"
REGION="us-central1"

# Check if bucket already exists
if gsutil ls -b gs://$BUCKET_NAME &>/dev/null; then
    echo -e "${YELLOW}Bucket already exists:${NC} gs://$BUCKET_NAME"
else
    echo "Creating GCS bucket for Terraform state..."
    
    # Enable Storage API
    if run_command "gcloud services enable storage.googleapis.com" "Enable Cloud Storage API"; then
        echo -e "${GREEN}✓ Storage API enabled${NC}"
    fi
    
    # Create bucket
    if run_command "gsutil mb -p $PROJECT_ID -l $REGION gs://$BUCKET_NAME" "Create GCS bucket for Terraform state"; then
        echo -e "${GREEN}✓ Bucket created${NC}"
    fi
    
    # Enable versioning
    if run_command "gsutil versioning set on gs://$BUCKET_NAME" "Enable versioning on bucket"; then
        echo -e "${GREEN}✓ Versioning enabled${NC}"
    fi
    
    # Enable uniform bucket-level access
    if run_command "gsutil uniformbucketlevelaccess set on gs://$BUCKET_NAME" "Enable uniform bucket-level access"; then
        echo -e "${GREEN}✓ Uniform access enabled${NC}"
    fi
    
    # Enable public access prevention
    if run_command "gsutil pap set enforced gs://$BUCKET_NAME" "Enable public access prevention"; then
        echo -e "${GREEN}✓ Public access prevention enabled${NC}"
    fi
    
    # Grant current user permissions
    USER_EMAIL=$(gcloud config get-value account)
    if run_command "gsutil iam ch user:${USER_EMAIL}:roles/storage.objectAdmin gs://${BUCKET_NAME}" "Grant bucket permissions to current user"; then
        echo -e "${GREEN}✓ Permissions granted${NC}"
    fi
    
    echo -e "${GREEN}✓ Bucket created and configured${NC}"
fi

# Create or update backend.tf
BACKEND_FILE="terraform/backend.tf"
echo ""
echo "Creating/updating terraform/backend.tf..."
mkdir -p terraform
log_command "cat > $BACKEND_FILE << EOF
terraform {
  backend \"gcs\" {
    bucket = \"${BUCKET_NAME}\"
    prefix = \"terraform/state\"
  }
}
EOF"
cat > $BACKEND_FILE << EOF
terraform {
  backend "gcs" {
    bucket = "${BUCKET_NAME}"
    prefix = "terraform/state"
  }
}
EOF
echo -e "${GREEN}✓ backend.tf updated with bucket: ${BUCKET_NAME}${NC}"

echo ""

# Step 6: Terraform Variables Configuration
echo -e "${BLUE}Step 6: Terraform Variables Configuration${NC}"
echo ""

TFVARS_FILE="terraform/terraform.tfvars"

if [ -f "$TFVARS_FILE" ]; then
    echo -e "${YELLOW}local terraform.tfvars already exists at ${TFVARS_FILE}${NC}"
    read -p "Do you want to overwrite it? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping terraform.tfvars creation"
        
        # Show summary and exit
        echo ""
        echo "=========================================="
        echo -e "${GREEN}Setup Complete!${NC}"
        echo "=========================================="
        echo ""
        echo "Next Steps (2-step deployment to avoid Kubernetes provider issues):"
        echo "  1. cd terraform/"
        echo "  2. export CLOUDFLARE_API_TOKEN=\$(gcloud secrets versions access latest --secret=\"cloudflare-api-token\")"
        echo "  3. terraform init"
        echo "  4. terraform apply -target=google_container_node_pool.primary_nodes"
        echo "  5. terraform apply"
        echo ""
        exit 0
    fi
fi

# Gather information for terraform.tfvars
echo ""
echo "Let's configure your Terraform variables..."
echo -e "${YELLOW}Press Enter to accept defaults shown in [brackets]${NC}"
echo ""

# Project ID (already set)
TF_PROJECT_ID=$PROJECT_ID
echo -e "Project ID: ${GREEN}${TF_PROJECT_ID}${NC}"

# Region
TF_REGION="us-central1"
read -p "Region [${TF_REGION}]: " INPUT_REGION
TF_REGION=${INPUT_REGION:-$TF_REGION}

# GKE Cluster Name
TF_CLUSTER_NAME="infra-seed-cluster"
read -p "GKE Cluster Name [${TF_CLUSTER_NAME}]: " INPUT_CLUSTER
TF_CLUSTER_NAME=${INPUT_CLUSTER:-$TF_CLUSTER_NAME}

# Artifact Registry Name
TF_REGISTRY_NAME="infra-seed-registry"
read -p "Artifact Registry Name [${TF_REGISTRY_NAME}]: " INPUT_REGISTRY
TF_REGISTRY_NAME=${INPUT_REGISTRY:-$TF_REGISTRY_NAME}

# GitHub Repo Owner (try to infer from git remote)
GIT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
if [[ $GIT_REMOTE =~ github\.com[:/]([^/]+)/ ]]; then
    DEFAULT_OWNER="${BASH_REMATCH[1]}"
    read -p "GitHub Username/Org [${DEFAULT_OWNER}]: " INPUT_OWNER
    TF_GITHUB_OWNER=${INPUT_OWNER:-$DEFAULT_OWNER}
else
    read -p "GitHub Username/Org (required): " TF_GITHUB_OWNER
    while [ -z "$TF_GITHUB_OWNER" ]; do
        echo -e "${RED}GitHub username/org is required${NC}"
        read -p "GitHub Username/Org: " TF_GITHUB_OWNER
    done
fi

# GitHub Repo Name (try to infer from git remote)
if [[ $GIT_REMOTE =~ github\.com[:/][^/]+/([^.]+) ]]; then
    DEFAULT_REPO="${BASH_REMATCH[1]}"
    read -p "GitHub Repo Name [${DEFAULT_REPO}]: " INPUT_REPO
    TF_GITHUB_REPO=${INPUT_REPO:-$DEFAULT_REPO}
else
    TF_GITHUB_REPO="infra-seed"
    read -p "GitHub Repo Name [${TF_GITHUB_REPO}]: " INPUT_REPO
    TF_GITHUB_REPO=${INPUT_REPO:-$TF_GITHUB_REPO}
fi

# Domain Name
read -p "Domain Name (required, e.g., example.com): " TF_DOMAIN
while [ -z "$TF_DOMAIN" ]; do
    echo -e "${RED}Domain name is required${NC}"
    read -p "Domain Name: " TF_DOMAIN
done

# Cloudflare Proxy
TF_CF_PROXY="true"
echo ""
echo -e "${YELLOW}Cloudflare Proxy:${NC}"
echo "  true  = Hide origin IP (recommended for production)"
echo "  false = Show origin IP (easier for initial testing)"
read -p "Enable Cloudflare Proxy? [true]: " INPUT_PROXY
TF_CF_PROXY=${INPUT_PROXY:-$TF_CF_PROXY}

# API Subdomain
TF_API_SUBDOMAIN="true"
read -p "Enable API subdomain (api.${TF_DOMAIN})? [true]: " INPUT_API
TF_API_SUBDOMAIN=${INPUT_API:-$TF_API_SUBDOMAIN}

# Create terraform.tfvars
echo ""
echo "Creating terraform.tfvars..."
log_command "cat > $TFVARS_FILE << EOF
# Terraform Variables
# Generated by scripts/init.sh

# GCP Configuration
project_id = \"${TF_PROJECT_ID}\"
region = \"${TF_REGION}\"
gke_cluster_name = \"${TF_CLUSTER_NAME}\"
artifact_registry_name = \"${TF_REGISTRY_NAME}\"

# GitHub Configuration
github_owner = \"${TF_GITHUB_OWNER}\"
github_repo_name = \"${TF_GITHUB_REPO}\"

# Domain Configuration
domain_name = \"${TF_DOMAIN}\"
cloudflare_proxy_enabled = ${TF_CF_PROXY}
enable_api_subdomain = ${TF_API_SUBDOMAIN}
EOF"
cat > $TFVARS_FILE << EOF
# Terraform Variables
# Generated by scripts/init.sh

# GCP Configuration
project_id = "${TF_PROJECT_ID}"
region = "${TF_REGION}"
gke_cluster_name = "${TF_CLUSTER_NAME}"
artifact_registry_name = "${TF_REGISTRY_NAME}"

# GitHub Configuration
github_owner = "${TF_GITHUB_OWNER}"
github_repo_name = "${TF_GITHUB_REPO}"

# Domain Configuration
domain_name = "${TF_DOMAIN}"
cloudflare_proxy_enabled = ${TF_CF_PROXY}
enable_api_subdomain = ${TF_API_SUBDOMAIN}
EOF

echo -e "${GREEN}✓ terraform.tfvars created${NC}"

# Final Summary
echo ""
echo "=========================================="
echo -e "${GREEN}Configuration Summary${NC}"
echo "=========================================="
echo ""
echo "GCP:"
echo "  Project ID:   ${TF_PROJECT_ID}"
echo "  Region:       ${TF_REGION}"
echo "  Cluster:      ${TF_CLUSTER_NAME}"
echo "  Registry:     ${TF_REGISTRY_NAME}"
echo ""
echo "GitHub:"
echo "  Owner:        ${TF_GITHUB_OWNER}"
echo "  Repo:         ${TF_GITHUB_REPO}"
echo ""
echo "Domain:"
echo "  Name:         ${TF_DOMAIN}"
echo "  CF Proxy:     ${TF_CF_PROXY}"
echo "  API Subdomain: ${TF_API_SUBDOMAIN}"
echo ""
echo "Files Created:"
echo "  ✓ ${BACKEND_FILE}"
echo "  ✓ ${TFVARS_FILE}"
echo ""
echo "Secrets:"
echo "  ✓ cloudflare-api-token (in Secret Manager)"
echo ""

# Step 7: GitHub Token Scope Check
echo ""
echo -e "${BLUE}Step 7: GitHub Token Scope Check${NC}"
echo ""

# Check if gh CLI is installed
if command -v gh &> /dev/null; then
    echo "Checking GitHub CLI authentication..."
    
    # Check if authenticated
    if gh auth status &>/dev/null; then
        echo -e "${GREEN}✓ GitHub CLI is authenticated${NC}"
        
        # Get current scopes
        CURRENT_SCOPES=$(gh auth token | xargs -I {} curl -s -H "Authorization: Bearer {}" https://api.github.com/users/$(gh api user -q .login) -I 2>/dev/null | grep -i "x-oauth-scopes:" | cut -d: -f2 | tr -d ' ')
        
        echo ""
        echo "Current token scopes: ${CURRENT_SCOPES}"
        echo ""
        
        # Check for required scopes
        MISSING_SCOPES=()
        
        # Check if repo scope is present
        if echo "$CURRENT_SCOPES" | grep -q "repo"; then
            echo -e "${GREEN}✓ Token has 'repo' scope (required for repository operations)${NC}"
        else
            echo -e "${YELLOW}⚠ Token missing 'repo' scope${NC}"
            MISSING_SCOPES+=("repo")
        fi
        
        # Check if workflow scope is present
        if echo "$CURRENT_SCOPES" | grep -q "workflow"; then
            echo -e "${GREEN}✓ Token has 'workflow' scope (required for .github/workflows/)${NC}"
        else
            echo -e "${YELLOW}⚠ Token missing 'workflow' scope${NC}"
            MISSING_SCOPES+=("workflow")
        fi
        
        # If there are missing scopes, offer to add them
        if [ ${#MISSING_SCOPES[@]} -gt 0 ]; then
            echo ""
            echo "The following scopes are required for GitHub automation:"
            for scope in "${MISSING_SCOPES[@]}"; do
                echo "  - $scope"
            done
            echo ""
            echo "Current scopes: ${CURRENT_SCOPES}"
            echo "Required scopes: repo, workflow"
            echo "Optional scopes: delete_repo (for terraform destroy)"
            echo ""
            read -p "Add missing scopes now? (y/n) " -n 1 -r
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                # Build new scopes list
                if [ -n "$CURRENT_SCOPES" ]; then
                    NEW_SCOPES="$CURRENT_SCOPES"
                    for scope in "${MISSING_SCOPES[@]}"; do
                        NEW_SCOPES="${NEW_SCOPES},${scope}"
                    done
                else
                    NEW_SCOPES=$(IFS=,; echo "${MISSING_SCOPES[*]}")
                fi
                # Remove leading/trailing commas and spaces
                NEW_SCOPES=$(echo "$NEW_SCOPES" | sed 's/^,//; s/,$//; s/ //g')
                
                if run_command "gh auth refresh --scopes \"$NEW_SCOPES\"" "Add missing scopes to GitHub token"; then
                    echo -e "${GREEN}✓ Scopes added${NC}"
                    
                    # Verify new scopes
                    UPDATED_SCOPES=$(gh auth token | xargs -I {} curl -s -H "Authorization: Bearer {}" https://api.github.com/users/$(gh api user -q .login) -I 2>/dev/null | grep -i "x-oauth-scopes:" | cut -d: -f2 | tr -d ' ')
                    echo "Updated scopes: ${UPDATED_SCOPES}"
                else
                    echo -e "${YELLOW}⚠ Could not add scopes automatically${NC}"
                    echo "You can add them manually later with: gh auth refresh --scopes \"repo,workflow,delete_repo\""
                fi
            else
                echo -e "${YELLOW}⚠ Skipping scope addition${NC}"
                echo "Note: You'll need to add these scopes manually to use GitHub automation features"
                echo "Run: gh auth refresh --scopes \"repo,workflow,delete_repo\""
            fi
        fi
    
    # Check for delete_repo scope (optional but helpful)
    echo ""
    if echo "$CURRENT_SCOPES" | grep -q "delete_repo"; then
        echo -e "${GREEN}✓ Token has 'delete_repo' scope (optional, for terraform destroy)${NC}"
    else
        echo -e "${YELLOW}ℹ Token missing 'delete_repo' scope (optional)${NC}"
        echo ""
        echo "The 'delete_repo' scope is optional but helpful if you plan to destroy"
        echo "Terraform-managed repositories with 'terraform destroy'."
        echo ""
        echo "You can add it later if needed with:"
        echo "  gh auth refresh --scopes \"repo,workflow,delete_repo\""
    fi
    else
        echo -e "${YELLOW}GitHub CLI is installed but not authenticated${NC}"
        echo ""
        echo "To use GitHub automation features, authenticate with proper scopes:"
        echo "  gh auth login --scopes \"repo,workflow\""
        echo ""
        read -p "Authenticate now? (y/n) " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if run_command "gh auth login --scopes \"repo,workflow\"" "Authenticate GitHub CLI with required scopes"; then
                echo -e "${GREEN}✓ GitHub CLI authenticated with workflow scope${NC}"
            else
                echo -e "${YELLOW}⚠ GitHub authentication skipped${NC}"
            fi
        else
            echo -e "${YELLOW}GitHub authentication skipped${NC}"
        fi
    fi
else
    echo -e "${YELLOW}GitHub CLI (gh) not found${NC}"
    echo ""
    echo "GitHub CLI is recommended for GitHub automation features."
    echo "Without it, you'll need to provide a Personal Access Token with 'repo' and 'workflow' scopes."
    echo ""
    echo "Install GitHub CLI:"
    echo "  macOS: brew install gh"
    echo "  Linux: See https://github.com/cli/cli#installation"
    echo ""
    echo "After installation, authenticate with:"
    echo "  gh auth login --scopes \"repo,workflow\""
fi

echo ""

# Step 8: Application Default Credentials
echo ""
echo -e "${BLUE}Step 8: Application Default Credentials${NC}"
echo ""
echo "Terraform requires application default credentials to authenticate with GCP."
if run_command "gcloud auth application-default login" "Set up application default credentials for Terraform"; then
    echo -e "${GREEN}✓ Application default credentials configured${NC}"
else
    echo -e "${RED}Failed to set up application default credentials${NC}"
    echo "This is required for Terraform to work."
    exit 1
fi

# Final Instructions
echo ""
echo "=========================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "=========================================="
echo ""

# Export environment variables for immediate use
echo -e "${BLUE}Step 9: Setting up environment variables${NC}"
echo ""

# Export Cloudflare API Token
echo "Exporting CLOUDFLARE_API_TOKEN..."
export CLOUDFLARE_API_TOKEN=$(gcloud secrets versions access latest --secret="cloudflare-api-token")
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ CLOUDFLARE_API_TOKEN exported${NC}"
else
    echo -e "${RED}✗ Failed to export CLOUDFLARE_API_TOKEN${NC}"
fi

# Export GitHub Token (if gh CLI is available)
if command -v gh &> /dev/null; then
    echo ""
    echo "Exporting GITHUB_TOKEN from GitHub CLI..."
    export GITHUB_TOKEN=$(gh auth token 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$GITHUB_TOKEN" ]; then
        echo -e "${GREEN}✓ GITHUB_TOKEN exported from gh CLI${NC}"
    else
        echo -e "${YELLOW}⚠ Could not get token from gh CLI${NC}"
        echo "  If you need GitHub automation, run: export GITHUB_TOKEN=\$(gh auth token)"
    fi
else
    echo ""
    echo -e "${YELLOW}GitHub CLI (gh) not found${NC}"
    echo "  For GitHub automation features, install gh CLI or set GITHUB_TOKEN manually"
fi

echo ""
echo -e "${YELLOW}Note: Environment variables are only available in the current shell session.${NC}"
echo -e "${YELLOW}For persistent access, add export commands to your shell profile (~/.bashrc, ~/.zshrc, etc.)${NC}"

echo ""

# Step 10: Initialize Terraform
echo -e "${BLUE}Step 10: Initialize Terraform${NC}"
echo ""

echo "Initializing Terraform..."
if run_command "(cd terraform && terraform init --reconfigure)" "Initialize Terraform with backend configuration"; then
    echo -e "${GREEN}✓ Terraform initialized${NC}"
else
    echo -e "${RED}Failed to initialize Terraform${NC}"
    exit 1
fi

echo ""

# Step 11: Terraform Plan & Apply - Phase 1 (GKE Cluster)
echo -e "${BLUE}Step 11: Phase 1 - Deploy GKE Cluster${NC}"
echo ""
echo "Creating plan for GKE cluster and node pool..."
echo "(Deploying cluster first ensures Kubernetes provider can use kubernetes_manifest resources)"

if run_command "(cd terraform && terraform plan -target=google_container_cluster.primary -target=google_container_node_pool.primary_nodes -out=tfplan-phase1)" "Create Terraform plan for GKE cluster"; then
    echo -e "${GREEN}✓ Phase 1 plan created (saved to terraform/tfplan-phase1)${NC}"
else
    echo -e "${RED}Failed to create Phase 1 plan${NC}"
    exit 1
fi

echo ""
echo "Applying Phase 1 plan..."
if run_command "(cd terraform && terraform apply tfplan-phase1)" "Deploy GKE cluster and node pool"; then
    echo -e "${GREEN}✓ GKE cluster deployed${NC}"
else
    echo -e "${RED}Failed to deploy GKE cluster${NC}"
    echo "You may need to manually run: cd terraform && terraform apply -target=google_container_node_pool.primary_nodes"
    exit 1
fi

echo ""
echo "Fetching cluster credentials for kubectl..."
if run_command "gcloud container clusters get-credentials ${TF_CLUSTER_NAME} --region=${TF_REGION} --project=${TF_PROJECT_ID}" "Get GKE cluster credentials"; then
    echo -e "${GREEN}✓ Cluster credentials configured${NC}"
else
    echo -e "${YELLOW}⚠ Failed to get cluster credentials${NC}"
    echo "You may need to manually run: gcloud container clusters get-credentials ${TF_CLUSTER_NAME} --region=${TF_REGION}"
    echo "Continuing anyway..."
fi

echo ""

# Step 12: Terraform Plan & Apply - Phase 2 (Remaining Infrastructure)
echo -e "${BLUE}Step 12: Phase 2 - Deploy Remaining Infrastructure${NC}"
echo ""
echo "Creating plan for remaining infrastructure (Kubernetes resources, Cloudflare DNS, etc.)..."

if run_command "(cd terraform && terraform plan -out=tfplan-phase2)" "Create Terraform plan for remaining infrastructure"; then
    echo -e "${GREEN}✓ Phase 2 plan created (saved to terraform/tfplan-phase2)${NC}"
else
    echo -e "${RED}Failed to create Phase 2 plan${NC}"
    exit 1
fi

echo ""
echo "Applying Phase 2 plan..."
if run_command "(cd terraform && terraform apply tfplan-phase2)" "Deploy all remaining infrastructure"; then
    echo -e "${GREEN}✓ Infrastructure deployed${NC}"
else
    echo -e "${RED}Failed to deploy infrastructure${NC}"
    echo "You may need to manually run: cd terraform && terraform apply"
    exit 1
fi

echo ""
echo "📝 Command Log:"
echo -e "   All executed commands have been saved to: ${YELLOW}$LOG_FILE${NC}"
echo "   You can review or re-run these commands manually if needed."
echo ""
echo "🎉 Infrastructure deployment complete!"
echo ""
echo "Next Steps:"
echo ""
echo "  1. Test your deployment:"
echo "     sh ./scripts/test.sh"
echo ""
echo "  2. Monitor deployment status:"
echo "     sh ./scripts/monitor.sh"
echo ""
echo "  3. For subsequent infrastructure changes:"
echo "  3. For subsequent infrastructure changes (after this initial setup):"
echo "     - Edit terraform/*.tf files as needed"
echo "     - sh ./scripts/auth.sh"
echo "     - cd terraform/"
echo "     - terraform plan"
echo "     - terraform apply"
echo "     (No need to re-run this init.sh script for future changes)"
echo ""

# Write completion section to log file
cat >> "$LOG_FILE" << 'EOF'
==========================================
Setup Complete!
==========================================

📝 Command Log:
   All executed commands have been saved to: init.log
   You can review or re-run these commands manually if needed.

🚀 Initial Terraform deployment complete!

Next Steps:

    1. Test your deployment:
        sh ./scripts/test.sh

    2. Monitor deployment status:
        sh ./scripts/monitor.sh

    3. For subsequent infrastructure changes (after this initial setup):
        - Edit terraform/*.tf files as needed
        - sh ./scripts/auth.sh
        - cd terraform/
        - terraform plan
        - terraform apply
        (No need to re-run this init.sh script for future changes)

    4. If you open a new terminal session, authenticate again:
        sh ./scripts/auth.sh

EOF
