Python API
==========

This directory contains the Python 3.x API for querying ntopng using the Python language.

This API is based on ntopng's [REST API](https://www.ntop.org/guides/ntopng/api/rest/api_v2.html) and it allows users to perform operations such as:
- Read host statistics
- Get the active flows list
- Query network interface stats
- Search historical flows

API Information
----------------
For each ntopng REST API call there is a corresponding Python method for the defined Python classes:
- [host](ntopng/host.py)
- [flow](ntopng/flow.py)
- [historical](ntopng/historical.py)
- [interface](ntopng/interface.py)

The [ntopng](ntopng/ntopng.py) class is used to store information such as ntopng IP address and credentials used to connect it.

The [test](test.py) application can be used as example of the Python API


Installation
------------
For you convenience, ntop periodically builds pip packages. You can install the latest available package as:
- `pip3 install ntopng`


Developing the Python API
-------------------------
We encourage our users to extend this API. For your convenience we are sharing a [Makefile](Makefile) that you can use as skeleton for installing the package locally or creating test packages.

Documentation
-------------
[ntopng REST API v2](https://www.ntop.org/guides/ntopng/api/rest/api_v2.html)
