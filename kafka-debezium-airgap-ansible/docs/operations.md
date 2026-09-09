# Runbook d'exploitation

## Contrôles courants

Relancer les contrôles sans réinstaller :

```bash
ansible-playbook verify.yml
```

État du quorum depuis un broker :

```bash
sudo -u kafka /opt/kafka/bin/kafka-metadata-quorum.sh \
  --bootstrap-server kafka01.mondomaine:9092 \
  --command-config /etc/kafka/kraft/broker-client.properties \
  describe --status
```

État des connecteurs :

```bash
curl -s http://127.0.0.1:8083/connectors?expand=status
```

Journaux :

```bash
journalctl -u kafka -f
journalctl -u kafka-connect -f
journalctl -u prometheus -u grafana-server -u akhq -f
```

## Ordre d'arrêt et de démarrage

Pour un arrêt planifié complet : mettez d'abord en pause ou arrêtez les connecteurs, arrêtez les workers Connect, puis les brokers un par un. Au redémarrage, démarrez les trois brokers et attendez un quorum sain avant Connect.

Pour une maintenance normale, ne redémarrez qu'un broker à la fois. Attendez qu'il réintègre le quorum et que le nombre de partitions hors ligne soit nul avant de poursuivre. Le `serial: 1` du play Kafka applique ce principe lors d'une nouvelle exécution du playbook.

## Sauvegardes indispensables

- `.state/` du contrôleur Ansible, chiffré et avec accès restreint ;
- inventaire, variables chiffrées et configuration des connecteurs ;
- configurations Grafana personnalisées si elles ne sont pas gérées comme code.

Les offsets, statuts et configurations Kafka Connect résident dans des topics internes répliqués à trois copies. Leur disponibilité dépend de Kafka ; ne les éditez pas manuellement.

## Surveillance prioritaire

- espace disque et latence I/O des brokers ;
- partitions hors ligne, ISR réduites et disponibilité du quorum ;
- retard des groupes consommateurs ;
- état des tâches Connect et métriques Debezium ;
- âge/taille des slots et WAL retenu dans PostgreSQL ;
- disponibilité et ancienneté des redo/archive logs Oracle ;
- durée et impact du snapshot initial.

Alertmanager est installé avec un receiver local vide. Configurez un relais SMTP ou webhook **interne** avant la production ; sinon les alertes seront visibles dans Prometheus mais ne seront pas transmises.

## Mises à jour

Les versions sont figées pour garantir la reproductibilité hors-ligne. Avant une mise à jour :

1. lire les notes de version Kafka, Debezium et des connecteurs ;
2. tester compatibilité, snapshots, DDL et reprise sur une plateforme identique ;
3. ajouter les nouveaux artefacts avec leurs SHA-512 ;
4. adapter les variables et chemins versionnés ;
5. mettre à jour Connect en rolling, puis Kafka selon le protocole de compatibilité de la version visée.

Ne remplacez pas silencieusement un binaire sous le même nom : les tâches d'extraction utilisent un marqueur d'installation et une mise à niveau doit rester une opération explicite.

