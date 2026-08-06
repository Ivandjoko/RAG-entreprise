# modules/ingestion/main.tf
#
# La ressource Lambda elle-même vit dans ingestion_lambda.tf (avec son layer de
# dépendances). Ce fichier ne sert plus qu'à documenter l'organisation du module :
# - s3.tf         : bucket des documents sources
# - dynamodb.tf   : table de métadonnées documents (indexée par doc_id)
# - dlq.tf        : file de dead-letter en cas d'échec d'ingestion
# - eventbridge.tf: déclenchement sur upload S3
# - iam_grants.tf : permissions IAM sur le bucket/table créés ici
