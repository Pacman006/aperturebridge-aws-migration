import io
from PIL import Image
from sqlalchemy import select
from frontend.application import application, new_asset
from shared.models import assets
from shared.settings import aws_client, get_engine
from worker.processor import process_object, process_message, make_thumbnail
import json


def png_bytes():
    data=io.BytesIO()
    Image.new('RGB',(1600,1000), (10,150,180)).save(data, format='PNG')
    return data.getvalue()


def test_file_validation_rejects_untrusted_inputs():
    import pytest
    for name, mime, size in [('', 'image/png', 10), ('x.exe','application/x-msdownload',12),
                              ('x.png','image/png',0), ('x.png','image/png',99999999)]:
        with pytest.raises(ValueError): new_asset(name,mime,size)
    asset = new_asset('../../holiday.png','image/png',20)
    assert asset['object_key'].startswith('raw/')
    assert '..' not in asset['object_key']


def test_local_upload_process_and_preview(sandbox):
    client=application.test_client()
    assert client.get('/healthz').status_code == 200
    assert client.get('/readyz').json['status'] == 'ready'
    r=client.post('/api/uploads/local', data={'file':(io.BytesIO(png_bytes()),'beach.png')},
                  content_type='multipart/form-data')
    assert r.status_code == 201, r.json
    uid = r.json['id']
    with get_engine().connect() as db:
        row=db.execute(select(assets).where(assets.c.id==uid)).mappings().one()
    assert row['status']=='PENDING'
    assert process_object('aperturebridge-test-bucket',row['object_key'])=='ready'
    assert process_object('aperturebridge-test-bucket',row['object_key'])=='already_done'
    recent=client.get('/api/assets')
    assert recent.status_code==200
    assert recent.json[0]['status']=='READY'
    assert recent.json[0]['preview_url'] == f'/api/assets/{uid}/preview'
    local_image = client.get(recent.json[0]['preview_url'])
    assert local_image.status_code == 200
    assert local_image.mimetype == 'image/jpeg'
    jpg=aws_client('s3').get_object(Bucket='aperturebridge-test-bucket',
        Key=f'processed/{uid}/preview.jpg')['Body'].read()
    with Image.open(io.BytesIO(jpg)) as photo:
        assert photo.size[0] <= 720
        assert photo.format == 'JPEG'


def test_bad_image_becomes_rejected(sandbox):
    client=application.test_client()
    r=client.post('/api/uploads/local', data={'file':(io.BytesIO(b'not really an image'),'fake.png')},
                  content_type='multipart/form-data')
    assert r.status_code==201
    with get_engine().connect() as con:
        row=con.execute(select(assets).where(assets.c.id==r.json['id'])).mappings().one()
    assert process_object('aperturebridge-test-bucket',row['object_key'])=='rejected'
    assert client.get('/api/assets').json[0]['status']=='REJECTED'


def test_local_only_route_closed_in_cloud_mode(sandbox, monkeypatch):
    monkeypatch.setenv('LOCAL_UPLOAD_PROXY','false')
    response=application.test_client().post('/api/uploads/local')
    assert response.status_code==404
    assert application.test_client().get('/api/assets/00000000-0000-0000-0000-000000000000/preview').status_code == 404


def test_worker_handles_s3_test_event_and_url_encoded_keys(sandbox, monkeypatch):
    process_message({'Body': json.dumps({'Event':'s3:TestEvent'})})
    events=[]
    monkeypatch.setattr('worker.processor.process_object',lambda bucket,key:events.append((bucket,key)))
    msg={'Records':[{'eventName':'ObjectCreated:Put','s3':{
        'bucket':{'name':'test-bucket'},'object':{'key':'raw%2Fabc%2Fspace+name.png'}}}]}
    process_message({'Body':json.dumps(msg)})
    assert events==[('test-bucket','raw/abc/space name.png')]


def test_thumbnail_fails_closed_on_oversize():
    import pytest
    with pytest.raises(ValueError): make_thumbnail(b'x'*(10*1024*1024+1))
