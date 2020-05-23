# Locate Service Usage

## Revision History

| Version  | Date       |  Major Changes  |
|----------|------------|-----------------|
| v2beta1  | 2020-05-21 | initial version |

## Introduction

The M-Lab Locate Service is a GCP hosted service that "locates" the best
M-Lab server for a user request. For different use cases, "best" could mean
different things. The sections below provide an overview of the locate
service operations and describe currently supported queries in more detail.

### Locate Servers Near the Client

#### When best means "geographically close"

GCP automatically adds client latitude and longitude to incoming [HTTP
request headers][headers]. The locate service uses this location to search
for nearby M-Lab servers that satisfy the client query.

[headers]: https://cloud.google.com/load-balancing/docs/user-defined-request-headers#how_user-defined_request_headers_work

The locate service also considers:

* is the target server online? (required)
* is the client request frequency [acceptable usage][aup]? (required)

> PLANNED(v2): the locate service will bias results to be in the same country
as the client.

The locate service returns up to four results for the requested measurement
service. The locate service may return fewer results when too few servers are
healthy in a geographic region. The locate service may return an error when
no servers are available.

> PLANNED(v2): in all cases above, the locate service will return a
recommended [v2.QueryResult.NextRequest][nextRequest] time and signed URL for
the client to issue the next request. This will make retry logic in clients
simpler and encourages best practices for the API. See the [request priority
hierarchy][priority].

[nextRequest]: https://godoc.org/github.com/m-lab/locate/api/v2#QueryResult
[priority]: https://godoc.org/github.com/m-lab/locate/api/v2
[aup]: https://www.measurementlab.net/aup

#### Query for Geographically Close Servers

The base URL for the locate service to query for geographically close
servers:

    http://locate.measurementlab.net/v2beta1/query/

Well formed requests must specify a service name. For example:

* ndt/ndt5 - NDT5 protocol for the NDT measurement service.
* ndt/ndt7 - NDT7 protocol for the NDT measurement service.

> PLANNED(v2): to discover the list of available services, the locate service
will support queries to the base URL.

A complete locate query request with service name (e.g. ndt/ndt7) looks like:

    http://locate.measurementlab.net/v2beta1/query/ndt/ndt7

A successful response will include a list of results. Each result object
includes the machine name and a map of "urls"; the key is the URL template
and the value is the complete URL to the service running on the target
machine. The template keys are static so clients can extract the value.

The complete URL includes the protocol scheme, e.g. `wss`, the machine name,
the resource path (e.g. `/ndt/v7/download`), and request parameters generated
by the locate service (e.g. `access_token=`). The `access_token=` request
parameter is validated by the target service (e.g. ndt-server). An invalid
access token will always be rejected.

    {
      "results": [
        {
          "machine": "mlab3-lga05.mlab-oti.measurement-lab.org",
          "urls": {
            "ws:///ndt/v7/download": "ws://ndt-mlab3-lga05.mlab-oti.measurement-lab.org/ndt/v7/download?access_token={{TOKEN}}",
            "ws:///ndt/v7/upload": "ws://ndt-mlab3-lga05.mlab-oti.measurement-lab.org/ndt/v7/upload?access_token={{TOKEN}}",
            "wss:///ndt/v7/download": "wss://ndt-mlab3-lga05.mlab-oti.measurement-lab.org/ndt/v7/download?access_token={{TOKEN}}",
            "wss:///ndt/v7/upload": "wss://ndt-mlab3-lga05.mlab-oti.measurement-lab.org/ndt/v7/upload?access_token={{TOKEN}}",
          }
        },
        ...
      ]
    }

> PLANNED(v2): to associate multiple measurements with the same session, the
locate service will add additional request parameters for `session=` with a
random id that the target server saves with the measurement.

Once a client connects to a target service using a given URL, the target
server may accept or reject the connection based on local conditions. The
goal is to preserve the expected measurement quality for every client,
occassionally at the cost of declining to run a measurement.

Therefore, the client must be resilient to transient rejections by continuing
with the next returned result. Clients must also gracefully handle the case
where all target servers reject the client request. This could happen when
the platform is under extreme load. Clients should report the outage to
users

> PLANNED(v2): once the `NextRequest` time is available, clients should wait
before trying again.
