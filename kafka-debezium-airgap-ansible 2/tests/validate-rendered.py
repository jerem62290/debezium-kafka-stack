#!/usr/bin/env python3
"""Contrôle sémantique des rendus de tests/render-templates.yml, sans serveur cible."""
import argparse
import configparser
import json
import re
import shlex
from pathlib import Path

import yaml


def properties(path):
    result = {}
    for line in path.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith(('#', '!')):
            continue
        key, value = line.split('=', 1)
        assert key not in result, f'Propriété dupliquée : {path.name} / {key}'
        result[key] = value
    return result


def jaas(text):
    # Garder les noms Java et FQDN comme des tokens entiers.
    lexer = shlex.shlex(text, posix=True, punctuation_chars='=;')
    lexer.whitespace_split = True
    tokens = list(lexer)
    assert tokens[:2] == ['org.apache.kafka.common.security.plain.PlainLoginModule', 'required']
    assert tokens[-1] == ';'
    values = {}
    for i in range(2, len(tokens) - 1, 3):
        key, equals, value = tokens[i:i + 3]
        assert equals == '=' and key not in values
        values[key] = value
    assert values['username'] and values['password']
    return values


def sasl(config, prefix=''):
    assert config[prefix + 'security.protocol'] == 'SASL_PLAINTEXT'
    assert config[prefix + 'sasl.mechanism'] == 'PLAIN'
    return jaas(config[prefix + 'sasl.jaas.config'])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('render_dir', type=Path)
    args = parser.parse_args()
    root = args.render_dir
    project = Path(__file__).resolve().parents[1]
    files = [p for p in root.rglob('*') if p.is_file()]
    assert len(files) >= 27, 'Rendus incomplets'
    for path in files:
        content = path.read_text()
        # Les légendes Grafana et annotations Prometheus contiennent légitimement {{ ... }}.
        assert '{%' not in content, path
        assert not re.search(r'(keystore|truststore|/pki/|--tls\.)', content), path
        if path.suffix in ('.yml', '.yaml'):
            yaml.safe_load(content)
        elif path.suffix == '.json':
            json.loads(content)

    broker = properties(root / 'kafka/server.properties')
    assert broker['listener.security.protocol.map'] == 'INTERNAL:SASL_PLAINTEXT,CONTROLLER:SASL_PLAINTEXT'
    assert broker['sasl.mechanism.inter.broker.protocol'] == 'PLAIN'
    assert broker['sasl.mechanism.controller.protocol'] == 'PLAIN'
    assert broker['allow.everyone.if.no.acl.found'] == 'false'
    assert broker['default.replication.factor'] == '3' and broker['min.insync.replicas'] == '2'
    internal = jaas(broker['listener.name.internal.plain.sasl.jaas.config'])
    controller = jaas(broker['listener.name.controller.plain.sasl.jaas.config'])
    superusers = {p.removeprefix('User:') for p in broker['super.users'].split(';')}
    assert {k.removeprefix('user_') for k in controller if k.startswith('user_')} == superusers

    worker = properties(root / 'connect/connect-distributed.properties')
    assert worker['listeners'] == 'http://0.0.0.0:8083'
    worker_identity = sasl(worker)
    identities = [sasl(properties(root / 'kafka/broker-client.properties')), worker_identity]
    for prefix in ('producer.', 'consumer.', 'admin.'):
        assert sasl(worker, prefix) == worker_identity
    secret = properties(root / 'connect/kafka-secrets.properties')
    assert jaas(secret['kafka.sasl.jaas.config']) == worker_identity

    akhq = yaml.safe_load((root / 'akhq/application.yml').read_text())
    assert akhq['micronaut']['server']['host'] == '0.0.0.0'
    assert akhq['micronaut']['security']['enabled'] is True
    assert akhq['akhq']['security']['default-group'] == 'no-roles'
    assert len(akhq['akhq']['security']['basic-auth']) == 2
    akhq_identity = sasl(akhq['akhq']['connections']['cdc-kafka']['properties'])
    identities.append(akhq_identity)
    assert sasl(properties(root / 'monitoring/toolbox-client.properties')) == akhq_identity
    exporter_secret = properties(root / 'monitoring/kafka-exporter-sasl.env')
    identities.append({'username': 'kafka-exporter', 'password': exporter_secret['SASL_USER_PASSWORD']})
    for identity in identities:
        assert internal['user_' + identity['username']] == identity['password']

    grafana = configparser.ConfigParser(interpolation=None)
    grafana.read(root / 'monitoring/grafana.ini')
    assert grafana['server']['http_addr'] == '0.0.0.0'
    assert grafana['server']['protocol'] == 'http'
    assert grafana['server']['domain'] != 'localhost'
    for name, port in [('prometheus', 9090), ('alertmanager', 9093)]:
        unit = (root / f'monitoring/{name}.service').read_text()
        assert f'--web.listen-address=0.0.0.0:{port}' in unit
    unit = (root / 'monitoring/kafka-exporter.service').read_text()
    assert '--sasl.enabled --sasl.mechanism=plain' in unit
    assert '--sasl.password' not in unit and 'EnvironmentFile=' in unit

    oracle = json.loads((project / 'examples/connectors/oracle-source.json').read_text())['config']
    for prefix in ('schema.history.internal.producer.', 'schema.history.internal.consumer.'):
        assert oracle[prefix + 'security.protocol'] == 'SASL_PLAINTEXT'
        assert oracle[prefix + 'sasl.mechanism'] == 'PLAIN'
        assert oracle[prefix + 'sasl.jaas.config'].endswith(':kafka.sasl.jaas.config}')
    assert not any('.ssl.' in key for key in oracle)
    assert not list((project / 'roles/pki_controller').rglob('*.*'))
    print(f'OK : {len(files)} rendus ; SASL cohérent, ACL conservées, interfaces ouvertes et aucune dépendance PKI.')


if __name__ == '__main__':
    main()
