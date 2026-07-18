from sqlalchemy import create_engine, Column, String, Float
from sqlalchemy.orm import declarative_base, sessionmaker
from config import DATABASE_URL

Base = declarative_base()

class Landmark(Base):
    __tablename__ = 'landmarks'
    id = Column(String, primary_key=True)
    name = Column(String, nullable=False)
    description = Column(String, default="")
    image_url = Column(String, nullable=False) # Local relative URL
    descriptor_path = Column(String, nullable=False) # Path to descriptor .npy file
    touch_x = Column(Float, nullable=False) # Relative x position (0.0 to 1.0)
    touch_y = Column(Float, nullable=False) # Relative y position (0.0 to 1.0)
    form_schema = Column(String, default="[]") # JSON string containing fields list

# Initialize Session
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def init_db():
    Base.metadata.create_all(bind=engine)
