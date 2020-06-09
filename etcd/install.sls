# -*- coding: utf-8 -*-
# vim: ft=yaml
{% from "etcd/map.jinja" import etcd with context -%}

  {% if etcd.manage_users == true %}
etcd-user-group-home:
  group.present:
    - name: {{ etcd.group or 'etcd' }}
    - system: True
  user.present:
    - name: {{ etcd.user or 'etcd' }}
    - gid_from_name: true
    - home: {{ etcd.prefix }}
    - require_in:
      - file: etcd-user-envfile
  {% endif %}

# install certs if provided
{%- if etcd.cert_src_path is defined and etcd.cert_dst_path is defined %}
etcd-cert-dir:
  file.directory:
    - name: {{ etcd.cert_dst_path }}
    - user: {{ etcd.user }}
    - group: {{ etcd.group }}
    - dirmode: 750
    - filemode: 644
    - makedirs: True
    - require:
      - user: {{ etcd.user or 'etcd' }}
      - group: {{ etcd.group or 'etcd' }}

{%- for file in
  'apiserver-etcd-client-key.pem',
  'apiserver-etcd-client.pem',
  'etcdctl-etcd-client-key.pem',
  'etcdctl-etcd-client.pem',
  'peer-key.pem',
  'peer.pem'
%}
"{{ etcd.cert_dst_path }}/{{ file }}":
  file.managed:
  - source: "{{ etcd.cert_src_path }}/{{ grains["nodename"] }}/{{ file }}"
  - user: etcd
  - group: etcd
  - mode: 644
  - require:
    - file: etcd-cert-dir
{%- endfor %}

{%- for file in
  'server-key.pem',
  'server.pem',
  'ca.pem'
%}
"{{ etcd.cert_dst_path }}/{{ file }}":
  file.managed:
  - source: "{{ etcd.cert_src_path }}/{{ file }}"
  - user: etcd
  - group: etcd
  - mode: 644
  - require:
    - file: etcd-cert-dir
{%- endfor %}
{%- endif %}

etcd-extract-dirs:
  file.directory:
    - makedirs: True
    - require_in:
      - etcd-download-archive
    - names:
      - {{ etcd.tmpdir }}
      - {{ etcd.prefix }}
    - unless: test -f {{ etcd.realhome }}/{{ etcd.command }}

etcd-other-dirs:
  file.directory:
    - makedirs: True
    - require_in:
      - etcd-download-archive
    - names:
      - {{ etcd.datadir }}
  {% if etcd.manage_users %}
    - user: {{ etcd.user or 'etcd' }}
    - group: {{ etcd.group or 'etcd' }}
    - recurse:
      - user
      - group
    - require_in:
      - file: etcd-user-envfile

etcd-user-envfile:
  file.managed:
    - name: {{ etcd.prefix }}/env4etcd.sh
    - source: salt://etcd/files/env4etcd.sh
    - template: jinja
    - mode: 644
    - user: {{ etcd.user or 'etcd' }}
    - group: {{ etcd.group or 'etcd' }}
    - context:
      etcd: {{ etcd|json }}

  {% endif %}

{% if etcd.use_upstream_repo|lower == 'true' %}

etcd-download-archive:
  cmd.run:
    - name: curl {{ etcd.dl.opts }} -o '{{ etcd.tmpdir }}{{ etcd.dl.archive_name }}' {{ etcd.dl.src_url }}
    - retry:
        attempts: {{ etcd.dl.retries }}
        interval: {{ etcd.dl.interval }}
    - unless: test -f {{ etcd.realhome }}/{{ etcd.command }}

    {%- if etcd.src_hashsum and grains['saltversioninfo'] <= [2016, 11, 6] %}
etcd-check-archive-hash:
   module.run:
     - name: file.check_hash
     - path: '{{ etcd.tmpdir }}/{{ etcd.dl.archive_name }}'
     - file_hash: {{ etcd.src_hashsum }}
     - onchanges:
       - cmd: etcd-download-archive
     - require_in:
       - archive: etcd-install
    {%- endif %}
{% elif etcd.use_upstream_repo|lower == 'custom' %}
etcd-download-archive:
  file.managed:
    - name: "{{ etcd.tmpdir }}/{{ etcd.dl.archive_name }}"
    - source: "{{ etcd.custom_download_url_prefix }}/{{ etcd.dl.archive_name }}"
    - unless: test -f {{ etcd.realhome }}/{{ etcd.command }}
{% endif %}

etcd-install:
{% if grains.os == 'MacOS' and etcd.use_upstream_repo|lower == 'homebrew' %}
  pkg.installed:
    - name: {{ etcd.pkg }}
    - version: {{ etcd.version }}
{% else %}
  archive.extracted:
    - source: 'file://{{ etcd.tmpdir }}/{{ etcd.dl.archive_name }}'
    - name: '{{ etcd.prefix }}'
    - archive_format: {{ etcd.dl.format.split('.')[0] }}
    - unless: test -f {{ etcd.realhome }}{{ etcd.command }}
    - watch_in:
      - service: etcd_{{ etcd.service_name }}_running
    - onchanges:
    {%- if etcd.use_upstream_repo|lower == 'custom' %}
      - file: etcd-download-archive
    {%- else %}
      - cmd: etcd-download-archive
    {%- endif %}
    {%- if etcd.src_hashurl and grains['saltversioninfo'] > [2016, 11, 6] %}
    - source_hash: {{ etcd.src_hashurl }}
    {%- endif %}
  
{% endif %}

