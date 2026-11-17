"""One-time, VPC-local Aurora initialization using a separate privileged ECS task."""
import json
import logging
from sqlalchemy import text
from shared.models import metadata
from shared.settings import get_engine, db_identity

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("aperturebridge.schema")


def main():
    engine = get_engine(admin=True)
    app_user, app_password = db_identity(admin=False)
    if app_user != "aperture_app":
        raise ValueError("Unexpected DB application user")
    # Use raw driver parameters; never assemble passwords into SQL strings.
    with engine.begin() as con:
        db = con.exec_driver_sql("SELECT DATABASE()").scalar_one()
        if db != "aperturebridge":
            logger.info("Initializing database %s", db)
        con.exec_driver_sql("CREATE USER IF NOT EXISTS 'aperture_app'@'%' IDENTIFIED BY %s", (app_password,))
        con.exec_driver_sql("ALTER USER 'aperture_app'@'%' IDENTIFIED BY %s", (app_password,))
        quoted = "`" + db.replace("`", "``") + "`"
        con.exec_driver_sql(f"GRANT SELECT, INSERT, UPDATE ON {quoted}.* TO 'aperture_app'@'%' ")
    metadata.create_all(bind=engine)
    logger.info("Schema and least-privilege app account initialized")


if __name__ == "__main__":
    main()
