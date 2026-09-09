# Préparation des bases pour Debezium

Les connecteurs ne doivent être enregistrés qu'après validation de la version exacte de chaque moteur avec la matrice Debezium 3.1 et un test de charge représentatif.

## PostgreSQL

Un connecteur PostgreSQL Debezium capture une base logique avec un slot de réplication dédié. Pour chaque base :

1. confirmer la version, le mode d'hébergement et l'accès au plugin logique `pgoutput` ;
2. activer `wal_level=logical` ;
3. dimensionner `max_replication_slots` et `max_wal_senders` avec une marge ;
4. créer un compte de réplication au privilège minimal et lui donner le droit `SELECT` sur les tables capturées ;
5. affecter un nom de slot et une publication uniques, en minuscules ;
6. garantir une clé primaire ou définir explicitement `REPLICA IDENTITY` selon le besoin des consommateurs ;
7. surveiller la taille du WAL retenu par chaque slot.

Un worker Connect arrêté n'efface pas le slot : PostgreSQL continue à retenir du WAL. Une alerte sur l'espace disque et le retard du slot est donc indispensable. N'abandonnez un slot qu'après avoir confirmé que le connecteur associé ne reprendra plus.

Le modèle `examples/connectors/postgresql-source.json` utilise `pgoutput`, une publication filtrée et un snapshot initial. Le mode de snapshot doit être ajusté selon la taille de la base et la fenêtre disponible.

## Oracle

Avant toute configuration, collectez :

- version et niveau de correctifs ;
- édition et licences ;
- CDB/PDB ou non-CDB ;
- instance unique, RAC, Data Guard ou autre réplication ;
- jeu de caractères, taille des redo logs, politique ARCHIVELOG et rétention des archives ;
- volume du snapshot initial et débit de changements en pointe.

La capture LogMiner nécessite généralement ARCHIVELOG, une journalisation supplémentaire adaptée, un compte technique et des droits de consultation du catalogue et des journaux. La liste exacte des privilèges et les paramètres changent selon la version et la topologie : ne copiez pas un script générique en production avant d'avoir identifié ces éléments.

Le connecteur exemple choisit LogMiner avec `online_catalog`. D'autres stratégies peuvent être préférables selon le taux de DDL, le volume et la version Oracle. XStream constitue une autre voie technique mais peut avoir des implications de licence ; faites valider ce point par Oracle et votre service juridique/achats.

Les archives redo doivent rester disponibles pendant toute indisponibilité plausible de Connect, avec une marge. Si le SCN requis n'est plus accessible, un nouveau snapshot peut devenir nécessaire.

## Secrets

Les modèles utilisent le `FileConfigProvider` de Kafka Connect. Exemple sur chaque worker :

```properties
database.password=mot-de-passe-fourni-par-le-coffre
```

Chemin : `/etc/kafka-connect/secrets/postgres-exemple.properties`, propriétaire `root:kafka-connect`, mode `0640`. En production, préférez un processus contrôlé alimenté par votre coffre-fort plutôt qu'une saisie manuelle.

## Convention recommandée

Utilisez un `topic.prefix` stable et unique par source, par exemple :

```text
pg.<application>.<environnement>
ora.<application>.<environnement>
```

Ne réutilisez jamais un slot PostgreSQL ni un topic d'historique Oracle entre deux connecteurs. Conservez les noms après mise en production : les changer modifie les topics et l'identité logique de la source.

