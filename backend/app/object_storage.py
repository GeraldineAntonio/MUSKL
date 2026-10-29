"""Private R2 storage for trainer certifications, profile photos and exercise media."""

from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path


class StorageNotConfigured(RuntimeError):
    pass


class StorageWriteError(RuntimeError):
    pass


class StorageReadError(RuntimeError):
    pass


def _settings() -> tuple[str, str, str, str] | None:
    account_id = os.getenv('MUSKL_R2_ACCOUNT_ID', '').strip()
    access_key = os.getenv('MUSKL_R2_ACCESS_KEY_ID', '').strip()
    secret_key = os.getenv('MUSKL_R2_SECRET_ACCESS_KEY', '').strip()
    bucket = os.getenv('MUSKL_R2_PRIVATE_BUCKET', '').strip()
    if not any((account_id, access_key, secret_key, bucket)):
        return None
    if not all((account_id, access_key, secret_key, bucket)):
        raise StorageNotConfigured('Faltan variables de configuración de R2.')
    return account_id, access_key, secret_key, bucket


@lru_cache(maxsize=1)
def _client(account_id: str, access_key: str, secret_key: str):
    import boto3

    return boto3.client(
        's3',
        endpoint_url=f'https://{account_id}.r2.cloudflarestorage.com',
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        region_name='auto',
    )


def configured() -> bool:
    return _settings() is not None


def put_certificate(key: str, data: bytes, content_type: str, local_dir: Path) -> str:
    settings = _settings()
    if settings:
        account_id, access_key, secret_key, bucket = settings
        try:
            _client(account_id, access_key, secret_key).put_object(
                Bucket=bucket,
                Key=key,
                Body=data,
                ContentType=content_type,
                CacheControl='private, no-store',
            )
        except Exception as exc:
            raise StorageWriteError('No se pudo guardar el certificado en R2.') from exc
        return f'r2://{key}'

    if os.getenv('MUSKL_ENV', 'development') != 'development':
        raise StorageNotConfigured('Configura el bucket privado de R2 antes de subir certificados.')

    destination = local_dir / key
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
    return f'local://{key}'


def presigned_certificate_url(storage_key: str, expires_in: int = 600) -> str:
    settings = _settings()
    if not settings:
        raise StorageNotConfigured('El almacenamiento privado de R2 no está configurado.')
    account_id, access_key, secret_key, bucket = settings
    key = storage_key.removeprefix('r2://')
    try:
        return _client(account_id, access_key, secret_key).generate_presigned_url(
            'get_object',
            Params={'Bucket': bucket, 'Key': key},
            ExpiresIn=expires_in,
        )
    except Exception as exc:
        raise StorageReadError('No se pudo generar el enlace del certificado.') from exc


def delete_certificate(storage_key: str) -> None:
    settings = _settings()
    if storage_key.startswith('r2://') and settings:
        account_id, access_key, secret_key, bucket = settings
        _client(account_id, access_key, secret_key).delete_object(
            Bucket=bucket, Key=storage_key.removeprefix('r2://'))


def put_profile_photo(key: str, data: bytes, content_type: str) -> str:
    settings = _settings()
    if not settings:
        raise StorageNotConfigured('Configura el bucket privado de R2 para guardar fotos de perfil.')
    account_id, access_key, secret_key, bucket = settings
    try:
        _client(account_id, access_key, secret_key).put_object(
            Bucket=bucket,
            Key=key,
            Body=data,
            ContentType=content_type,
            CacheControl='private, no-store',
        )
    except Exception as exc:
        raise StorageWriteError('No se pudo guardar la foto de perfil en R2.') from exc
    return f'r2://{key}'


def presigned_profile_photo_url(storage_key: str, expires_in: int = 600) -> str:
    settings = _settings()
    if not settings:
        raise StorageNotConfigured('El almacenamiento privado de R2 no está configurado.')
    account_id, access_key, secret_key, bucket = settings
    try:
        return _client(account_id, access_key, secret_key).generate_presigned_url(
            'get_object',
            Params={'Bucket': bucket, 'Key': storage_key.removeprefix('r2://')},
            ExpiresIn=expires_in,
        )
    except Exception as exc:
        raise StorageReadError('No se pudo generar el acceso temporal a la foto de perfil.') from exc


def delete_profile_photo(storage_key: str) -> None:
    settings = _settings()
    if storage_key.startswith('r2://') and settings:
        account_id, access_key, secret_key, bucket = settings
        _client(account_id, access_key, secret_key).delete_object(
            Bucket=bucket, Key=storage_key.removeprefix('r2://'))


def put_exercise_media(key: str, data: bytes, content_type: str) -> str:
    settings = _settings()
    if not settings:
        raise StorageNotConfigured('Configura el bucket privado de R2 para guardar videos de ejercicios.')
    account_id, access_key, secret_key, bucket = settings
    try:
        _client(account_id, access_key, secret_key).put_object(
            Bucket=bucket,
            Key=key,
            Body=data,
            ContentType=content_type,
            CacheControl='private, no-store',
        )
    except Exception as exc:
        raise StorageWriteError('No se pudo guardar el video del ejercicio en R2.') from exc
    return f'r2://{key}'


def presigned_exercise_media_url(storage_key: str, expires_in: int = 600) -> str:
    settings = _settings()
    if not settings:
        raise StorageNotConfigured('El almacenamiento privado de R2 no está configurado.')
    account_id, access_key, secret_key, bucket = settings
    try:
        return _client(account_id, access_key, secret_key).generate_presigned_url(
            'get_object',
            Params={'Bucket': bucket, 'Key': storage_key.removeprefix('r2://')},
            ExpiresIn=expires_in,
        )
    except Exception as exc:
        raise StorageReadError('No se pudo generar el enlace temporal del video.') from exc


def delete_exercise_media(storage_key: str) -> None:
    settings = _settings()
    if storage_key.startswith('r2://') and settings:
        account_id, access_key, secret_key, bucket = settings
        _client(account_id, access_key, secret_key).delete_object(
            Bucket=bucket, Key=storage_key.removeprefix('r2://'))

