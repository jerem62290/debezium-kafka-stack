# Place éventuelle de Spark et Apache Iceberg

Spark et Iceberg ne remplacent ni Debezium ni Kafka : ils répondent à un besoin différent, en aval du flux CDC.

## Quand les ajouter

Ils deviennent pertinents si vous souhaitez :

- conserver une histoire analytique longue à coût inférieur à Kafka ;
- reconstruire l'état courant de tables et interroger aussi leur historique ;
- joindre de gros volumes venant de plusieurs bases ;
- alimenter BI, data science ou traitements batch ;
- bénéficier du partitionnement, de l'évolution de schéma et du time travel d'Iceberg.

Une architecture cible typique serait : Kafka reçoit les événements Debezium, Spark Structured Streaming les transforme et les écrit dans des tables Iceberg stockées sur un stockage objet ou HDFS. Un catalogue Iceberg — REST, Hive Metastore, Nessie ou autre — gère les métadonnées.

## Quand ne pas les ajouter

Ils sont inutiles pour un consommateur applicatif qui veut simplement réagir aux changements en temps réel, répliquer quelques tables ou déclencher un traitement. Ils ajoutent un moteur de calcul, un stockage, un catalogue, des opérations de compaction et une nouvelle politique de sécurité/sauvegarde.

## Points de conception futurs

- destination : stockage objet S3 compatible interne ou HDFS ;
- catalogue Iceberg et haute disponibilité ;
- représentation des insertions, mises à jour et suppressions Debezium ;
- stratégie d'upsert/MERGE et déduplication at-least-once ;
- conservation des données sensibles et gouvernance ;
- fréquence des checkpoints, compactions et expiration des snapshots ;
- dimensionnement d'un cluster Spark séparé.

La bonne séquence est donc de stabiliser d'abord le CDC Kafka/Debezium et ses contrats de messages. Spark/Iceberg pourra être ajouté comme un groupe de consommateurs indépendant sans changer les producteurs ni le cluster Kafka.

