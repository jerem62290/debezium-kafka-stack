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
curl -fsS 'http://connect01.mondomaine:8083/connectors?expand=status'
```

Journaux :

```bash
journalctl -u kafka -f
journalctl -u kafka-connect -f
journalctl -u prometheus -u grafana-server -u akhq -f
```

## Ordre d'arrêt et de démarrage

Pour un arrêt planifié complet : mettez d'abord en pause ou arrêtez les connecteurs, arrêtez les workers Connect, puis les brokers un par un. Au redémarrage, démarrez les trois brokers et attendez un quorum sain avant Connect.

Pour une maintenance normale, ne redémarrez qu'un broker à la fois. Attendez qu'il réintègre le quorum et que le nombre de partitions hors ligne soit nul avant de poursuivre. Le `serial: 1` du play Kafka séquence les tâches par hôte, mais ne remplace pas votre contrôle des ISR entre redémarrages. Pour la conversion TLS vers SASL, ne pas procéder en rolling : voir [migration-no-pki.md](migration-no-pki.md).

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


## Réseau et accès administrateur

Les interfaces HTTP n'ont plus de filtre d'IP source dans le playbook. Grafana et AKHQ conservent leur login ; Connect, Prometheus et Alertmanager sont accessibles sans authentification.

Vérifiez sur la toolbox `ss -lnt`, `firewall-cmd --get-active-zones` et `firewall-cmd --zone=public --list-ports` (adaptez la zone). Testez les URL depuis chaque réseau utilisateur. Le contrôle intégré valide l'accès depuis le contrôleur Ansible, pas depuis tous les réseaux de l'entreprise.

Les exporters locaux Kafka et Blackbox restent sur `127.0.0.1`. Les ports JMX/Node Exporter et le quorum conservent leur politique réseau interne. Alertmanager ne crée pas de listener de gossip HA, puisqu'une seule instance est déployée.
