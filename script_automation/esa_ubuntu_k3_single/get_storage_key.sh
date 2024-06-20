#!/usr/bin/env bash

while getopts g:n:s: flag
do
    case "${flag}" in
        g) RESOURCE_GROUP=${OPTARG};;
        s) STORAGE_ACCOUNT=${OPTARG};;
        n) NAMESPACE=${OPTARG};;
    esac
done

SECRET=$(az storage account keys list -g $RESOURCE_GROUP -n $STORAGE_ACCOUNT --query [0].value --output tsv)

kubectl create secret generic -n "${NAMESPACE}" "${STORAGE_ACCOUNT}"-secret --from-literal=azurestorageaccountkey="${SECRET}" --from-literal=azurestorageaccountname="${STORAGE_ACCOUNT}"
