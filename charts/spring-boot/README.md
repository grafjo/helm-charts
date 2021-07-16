# Spring Boot

## Introduction

This chart bootstraps a Spring Boot deployment on a [Kubernetes](https://kubernetes.io) cluster
using the [Helm](https://helm.sh) package manager. The application will be configured via environment variables.

## Build Image

See [Container Images](https://docs.spring.io/spring-boot/docs/current/reference/htmlsingle/#boot-features-container-images)
in Spring Boot Reference.



## Configuration

The following table lists the configurable parameters of the Spring Boot chart and their default values.

```console
$ helm chart values grafjo/spring-boot
```



### Image

The default image is [grafjo/whoami](https://github.com/grafjo/whoami).

Please update to your needs via a custom values-file:

```yaml
image:
  repository: grafjo/whoami
  pullPolicy: IfNotPresent
  tag: "0.5.0"
```


### Usage of the `tpl` Function

The `tpl` function allows us to pass string values from `values.yaml` through the templating engine.
It is used for the following values:

* `extraEnv`
* `extraEnvFrom`
* `affinity`

It is important that these values be configured as strings. Otherwise, installation will fail.


### JVM Settings

The chart sets the following system properties by default:
`-XX:+PrintFlagsFinal`

You can override thes by setting the `JAVA_OPTS` environment variable.

```yaml
extraEnv: |
  - name: JAVA_OPTS
    value: >-
      -XX:+PrintFlagsFinal
      -Djava.net.preferIPv4Stack=true
      -Djava.awt.headless=true
```

### Environment Configuration By Example

```yaml
extraEnv: |
    - name: spring.datasource.url
      value: jdbc:mariadb://database-server:3306/my-database

extraEnvFrom: |
    - secretRef:
        name: '{{ include "spring-boot.fullname" . }}-database'

secrets:
  database:
    stringData:
      spring.datasource.username: '{{ .Values.db.username }}'
      spring.datasource.password: '{{ .Values.db.password }}'
```

### Spring Boot Actuator Settings

By default, the Spring Boot Actuator is using the same port as application.
Exposing all management endpoints by using the default HTTP port is a sensible thing.
It's possible to expose the management endpoints to a different port.
A new service will be created, but not exposed via an ingress!

```yaml
customizedManagementServer:
  enabled: true

livenessProbe: |
  httpGet:
    path: /actuator/health
    port: http-management
  initialDelaySeconds: 120
  periodSeconds: 10
  failureThreshold: 10

readinessProbe: |
  httpGet:
    path: /actuator/health
    port: http-management
  initialDelaySeconds: 60
  periodSeconds: 10
  failureThreshold: 10
```


### Prometheus Operator Support

```yaml
serviceMonitor:
  enabled: true
```

Running management on a different port:

```yaml
serviceMonitor:
  enabled: true
  port: http-management
```
