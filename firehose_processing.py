from __future__ import print_function

import base64

print('Loading function')


def handler(event, context):
    output = []
    newline = "\n"
    buffer = base64.b64encode(newline.encode("utf-8"))

    for record in event['records']:
        print(record['recordId'])
        payload = base64.b64decode(record['data'])

        # Do custom processing on the payload here

        output_record = {
            'recordId': record['recordId'],
            'result': 'Ok',
            'data': base64.b64encode(payload) + buffer
        }
        output.append(output_record)

    print('Successfully processed {} records.'.format(len(event['records'])))

    return {'records': output}
