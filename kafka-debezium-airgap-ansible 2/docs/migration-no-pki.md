# Passage de la version TLS à la version v1.1.0 sans PKI

Cette procédure ne concerne qu'une stack déjà installée. Pour une installation neuve, utilisez directement le README.

## Ce qui change

- Plus de rôle PKI, création de CA, certificats, keystores ou truststores.
- Kafka client et KRaft : `SASL_PLAINTEXT` avec mécanisme `PLAIN`.
- Identités broker/worker/AKHQ/exporter conservées par nom, donc ACL existantes réutilisables.
- Interfaces admin HTTP exposées sur `0.0.0.0` et ports ouverts sans restriction de source IP.
- Le bundle, les versions des composants, les répertoires de données et le cluster ID restent identiques.
- Aucune modification automatique de la configuration des bases, de leurs certificats ni des connecteurs déjà enregistrés.

## Interruption obligatoire

Les mêmes ports passent d'un protocole TLS à SASL non chiffré. Cette conversion n'est **pas** une migration rolling. Le contrôle `protocol_migration_guard` échoue avant les modifications des VM si une ancienne configuration TLS est détectée et qu'un service Kafka ou Connect est encore actif.

Le contrôle suppose les services systemd gérés par le projet, et ne détecte pas des processus Kafka démarrés manuellement. Vérifiez qu'aucun processus résiduel n'écoute sur les ports Kafka avant de relancer.

1. Sauvegarder l'ancien projet, `.state/`, les configurations des VM, les configurations complètes des connecteurs, les ACL et les personnalisations Grafana. Ne pas effacer ou reformater les répertoires de données.
2. Réserver une fenêtre d'interruption et vérifier la rétention des WAL/redo/archive logs pendant cet arrêt.
3. Mettre les connecteurs en pause, attendre la prise en compte, puis arrêter tous les workers Connect. Arrêter également les consommateurs métier.
4. Arrêter AKHQ et Kafka Exporter pour éviter leurs tentatives de reconnexion, puis arrêter les trois services Kafka. Ces arrêts sont des opérations planifiées à effectuer par l'exploitant ; le playbook ne les déclenche pas à votre place.
5. Extraire cette archive dans un **nouveau répertoire**, pas par-dessus les anciens rôles : cela évite de conserver des fichiers PKI obsolètes dans le code. Y reprendre l'inventaire, le bundle et le `.state/` du cluster existant, avec leurs permissions. Ne jamais reprendre un `.state` provenant d'un autre cluster.
6. Reprendre les personnalisations utiles, sans écraser les nouvelles valeurs. Supprimer les anciennes variables `ui_allowed_cidrs`, `connect_rest_allowed_cidrs`, `*_pki_dir` et secrets de keystore/truststore des overrides ; renommer `pki_extra_clients` en `kafka_extra_clients` en conservant les noms. Garder les comptes Grafana/AKHQ existants.
7. Exécuter `ansible-playbook site.yml` **sans --limit ni sélection de tags**, avec tous les hôtes disponibles. Le playbook génère les nouveaux mots de passe SASL, conserve le cluster ID et les données, puis démarre Kafka, les ACL, Connect et la toolbox.
8. Mettre à jour les configurations des clients externes : protocole `SASL_PLAINTEXT`, mécanisme `PLAIN`, identité et mot de passe SASL. Les anciens paramètres SSL ne doivent plus être utilisés.
9. Pour chaque connecteur Oracle existant, partir de sa **configuration réelle sauvegardée**, remplacer les propriétés `schema.history.internal.producer/consumer.ssl.*` par les paramètres SASL de l'exemple Oracle révisé. Vérifier aussi d'éventuels `producer.override.*` / `consumer.override.*` / `admin.override.*` SSL. Réappliquer la configuration réelle via l'API Connect, pas l'exemple tel quel. Conserver nom du connecteur, `topic.prefix`, topics d'historique, slots/publications et offsets.
10. Exécuter `ansible-playbook verify.yml`, tester les connexions et la capture, puis reprendre les connecteurs et consommateurs. Contrôler retard, erreurs d'authentification et éventuels doublons de reprise. Tester les URL admin depuis chaque réseau attendu.

## Identités et secrets

`.state/sasl/<identité>` contient les mots de passe Kafka. Les fichiers sur les VM sont protégés par les permissions, mais les échanges réseau restent en clair. Pour les consommateurs, fournir le secret par votre canal interne habituel ; ne pas le transmettre en clair dans un ticket.

Exemple de fichier client **à compléter avec un vrai secret** et à protéger en mode `0600` :

```properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="nom-consommateur" password="SECRET_A_FOURNIR";
```

Sur la toolbox, la CLI admin est disponible pour root :

```bash
sudo /opt/kafka-cli/bin/kafka-topics.sh \
  --bootstrap-server kafka01.mondomaine:9092 \
  --command-config /opt/kafka-cli/config/admin-client.properties \
  --list
```

L'ajout/suppression d'une identité PLAIN modifie la configuration des brokers. La rotation d'un mot de passe existant nécessite une procédure coordonnée pour les brokers et les clients ; elle n'est pas gérée sans interruption par cette variante. Le rôle ACL ajoute des droits mais ne révoque pas automatiquement les anciens.

## Anciens fichiers et retour arrière

Les anciens certificats déjà présents dans `.state/pki` et les répertoires PKI des VM ne sont **ni utilisés ni supprimés automatiquement**. Les fichiers générés par cette version ne les référencent plus. Archivez-les de façon sécurisée pour le retour arrière, puis faites leur retrait explicite selon votre politique de rétention. Les rôles et tests de génération PKI ont été retirés de la nouvelle archive ; l'archive d'origine reste une sauvegarde récupérable.

Un retour arrière nécessite à nouveau l'arrêt de Connect et Kafka, la restauration coordonnée des anciennes configurations/protocole et le démarrage dans l'ordre quorum → brokers → Connect → clients. Ne restaurez pas les données Kafka ou les offsets à une ancienne date uniquement pour revenir au TLS.
