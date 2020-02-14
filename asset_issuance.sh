#!/bin/bash
set -x
shopt -s expand_aliases

# ASSUMES elementsd IS ALREADY RUNNING

######################################################
#                                                    #
#    SCRIPT CONFIG - PLEASE REVIEW BEFORE RUNNING    #
#                                                    #
######################################################

# Amend the following:
NAME="BUCS TOKEN"
TICKER="BUCS"
# Do not use a domain prefix in the following:
DOMAIN="secondbase.github.io"
# Issue 100 assets using the satoshi unit, dependant on PRECISION when viewed from
# applications using Asset Registry data.
ASSET_AMOUNT=0.00000100
# Issue 1 reissuance token using the satoshi unit, unaffected by PRECISION.
TOKEN_AMOUNT=0.00000001

# Amend the following if needed:
PRECISION=0

# Don't change the following:
VERSION=0

# If your Liquid node has not seen enough transactions to calculate
# its own feerate you will need to specify one to prevent a 'feeRate'
# error. We'll assume this is the case:
FEERATE=0.00003000

# Change the following to point to your elements-cli binary and liquid data directory.
alias e1-cli="elements-cli"

##############################
#                            #
#    END OF SCRIPT CONFIG    #
#                            #
##############################

# Exit on error
set -o errexit

# We need to get a 'legacy' type (prefix 'CTE') address for this:
NEWADDR=$(e1-cli getnewaddress "" legacy)

VALIDATEADDR=$(e1-cli getaddressinfo $NEWADDR)

PUBKEY=$(echo $VALIDATEADDR | jq '.pubkey' | tr -d '"')

ASSET_ADDR=$NEWADDR

NEWADDR=$(e1-cli getnewaddress "" legacy)

TOKEN_ADDR=$NEWADDR

# Create the contract and calculate the contract hash.
# The contract is formatted for use in the Blockstream Asset Registry
# Do not amend the following!

CONTRACT='{"entity":{"domain":"'$DOMAIN'"},"issuer_pubkey":"'$PUBKEY'","name":"'$NAME'","precision":'$PRECISION',"ticker":"'$TICKER'","version":'$VERSION'}'

# We will hash using openssl, other options are available
CONTRACT_HASH=$(echo -n $CONTRACT | openssl dgst -sha256)
CONTRACT_HASH=$(echo ${CONTRACT_HASH#"(stdin)= "})

# Reverse the hash. This will be calculated from the contract by the asset registry service to
# check validity of the issuance against the registry entry.
TEMP=$CONTRACT_HASH

LEN=${#TEMP}

until [ $LEN -eq "0" ]; do
    END=${TEMP:(-2)}
    CONTRACT_HASH_REV="$CONTRACT_HASH_REV$END"
    TEMP=${TEMP::-2}
    LEN=$((LEN-2))
done

RAWTX=$(e1-cli createrawtransaction '''[]''' '''{"''data''":"''00''"}''')

# If your Liquid node has seen enough transactions to calculate its
# own feeRate then you can switch the two lines below. We'll default
# to specifying a fee rate:
#FRT=$(e1-cli fundrawtransaction $RAWTX)
FRT=$(e1-cli fundrawtransaction $RAWTX '''{"''feeRate''":'$FEERATE'}''')

HEXFRT=$(echo $FRT | jq '.hex' | tr -d '"')

RIA=$(e1-cli rawissueasset $HEXFRT '''[{"''asset_amount''":'$ASSET_AMOUNT', "''asset_address''":"'''$ASSET_ADDR'''", "''token_amount''":'$TOKEN_AMOUNT', "''token_address''":"'''$TOKEN_ADDR'''", "''blind''":false, "''contract_hash''":"'''$CONTRACT_HASH_REV'''"}]''')

# Details of the issuance...
HEXRIA=$(echo $RIA | jq '.[0].hex' | tr -d '"')
ASSET=$(echo $RIA | jq '.[0].asset' | tr -d '"')
ENTROPY=$(echo $RIA | jq '.[0].entropy' | tr -d '"')
TOKEN=$(echo $RIA | jq '.[0].token' | tr -d '"')

# Blind, sign and send the issuance transaction...
BRT=$(e1-cli blindrawtransaction $HEXRIA true '''[]''' false)

SRT=$(e1-cli signrawtransactionwithwallet $BRT)

HEXSRT=$(echo $SRT | jq '.hex' | tr -d '"')

# Test the transaction's acceptance into the mempool
TEST=$(e1-cli testmempoolaccept '''["'$HEXSRT'"]''')
ALLOWED=$(echo $TEST | jq '.[0].allowed' | tr -d '"')

# If the transaction is valid
if [ "true" = $ALLOWED ] ; then
    # Broadcast the transaction
    ISSUETX=$(e1-cli sendrawtransaction $HEXSRT)
else
    echo "ERROR SENDING TRANSACTION!"
fi

#####################################
#                                   #
#    ASSET REGISTRY FILE OUTPUTS    #
#                                   #
#####################################

# Blockstream's Liquid Asset Registry (https://assets.blockstream.info/) can be used to register an asset to an issuer.
# We already have the required data and have formatted the contract plain text into a format that we can use for this.

# Write the domain and asset ownership proof to a file. The file should then be placed over the entire lifecycle of
# the asset in a directory within the root of your domain named ".well-known"
# The file should have no extension and just copied as it is created.

echo "Authorize linking the domain name $DOMAIN to the Liquid asset $ASSET" > liquid-asset-proof-$ASSET

# After you have placed the above file without your domain you can run the register_asset.sh script created below to post the asset data to the registry.

echo "curl https://assets.blockstream.info/ --data-raw '{\"asset_id\":\"$ASSET\",\"contract\":$CONTRACT}'" > register_asset.sh

# For reference, write some asset details. These are not needed by the asset registry.

echo "ISSUETX:$ISSUETX ASSET:$ASSET ENTROPY:$ENTROPY TOKEN:$TOKEN ASSET_AMOUNT:$ASSET_AMOUNT TOKEN_AMOUNT:$TOKEN_AMOUNT ASSET_ADDR:$ASSET_ADDR TOKEN_ADDR:$TOKEN_ADDR CONTRACT_HASH_REV:$CONTRACT_HASH_REV" > liquid-asset-ref-$ASSET

##################################################################

echo "Completed without error"
