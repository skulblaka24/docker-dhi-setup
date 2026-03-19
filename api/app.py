import os
import json
import logging
from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
import redis
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Database configuration
db_user = os.getenv('POSTGRES_USER', 'taskuser')
db_password = os.getenv('POSTGRES_PASSWORD', 'taskpass')
db_host = os.getenv('POSTGRES_HOST', 'db')
db_port = os.getenv('POSTGRES_PORT', '5432')
db_name = os.getenv('POSTGRES_DB', 'taskdb')

app.config['SQLALCHEMY_DATABASE_URI'] = f'postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)

# Redis configuration
redis_host = os.getenv('REDIS_HOST', 'redis')
redis_port = int(os.getenv('REDIS_PORT', 6379))
redis_password = os.getenv('REDIS_PASSWORD', None)
cache = redis.Redis(
    host=redis_host,
    port=redis_port,
    password=redis_password,
    decode_responses=True,
    lib_name="",
    lib_version=""
)

# Database Models
class Task(db.Model):
    __tablename__ = 'tasks'

    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text)
    completed = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'title': self.title,
            'description': self.description,
            'completed': self.completed,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }

# Initialize database
with app.app_context():
    db.create_all()
    logger.info("Database tables created successfully")

# Helper functions
def invalidate_cache():
    """Invalidate the tasks list cache"""
    cache.delete('tasks:all')

def get_cached_tasks():
    """Get tasks from cache"""
    cached = cache.get('tasks:all')
    if cached:
        logger.info("Cache hit for tasks list")
        return json.loads(cached)
    return None

def set_cached_tasks(tasks):
    """Set tasks in cache with 60 second TTL"""
    cache.setex('tasks:all', 60, json.dumps(tasks))
    logger.info("Tasks list cached")

# Routes
@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    try:
        # Check database connection
        db.session.execute(db.text('SELECT 1'))

        # Check redis connection
        cache.ping()

        return jsonify({
            'status': 'healthy',
            'database': 'connected',
            'cache': 'connected'
        }), 200
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return jsonify({
            'status': 'unhealthy',
            'error': str(e)
        }), 503

@app.route('/tasks', methods=['GET'])
def get_tasks():
    """Get all tasks"""
    try:
        # Try to get from cache first
        cached_tasks = get_cached_tasks()
        if cached_tasks is not None:
            return jsonify(cached_tasks), 200

        # If not in cache, query database
        tasks = Task.query.order_by(Task.created_at.desc()).all()
        tasks_list = [task.to_dict() for task in tasks]

        # Cache the result
        set_cached_tasks(tasks_list)

        return jsonify(tasks_list), 200
    except Exception as e:
        logger.error(f"Error getting tasks: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/tasks/<int:task_id>', methods=['GET'])
def get_task(task_id):
    """Get a specific task"""
    try:
        task = Task.query.get_or_404(task_id)
        return jsonify(task.to_dict()), 200
    except Exception as e:
        logger.error(f"Error getting task {task_id}: {str(e)}")
        return jsonify({'error': str(e)}), 404

@app.route('/tasks', methods=['POST'])
def create_task():
    """Create a new task"""
    try:
        data = request.get_json()

        if not data or 'title' not in data:
            return jsonify({'error': 'Title is required'}), 400

        task = Task(
            title=data['title'],
            description=data.get('description', ''),
            completed=data.get('completed', False)
        )

        db.session.add(task)
        db.session.commit()

        # Invalidate cache
        invalidate_cache()

        logger.info(f"Created task: {task.id}")
        return jsonify(task.to_dict()), 201
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error creating task: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/tasks/<int:task_id>', methods=['PUT'])
def update_task(task_id):
    """Update a task"""
    try:
        task = Task.query.get_or_404(task_id)
        data = request.get_json()

        if 'title' in data:
            task.title = data['title']
        if 'description' in data:
            task.description = data['description']
        if 'completed' in data:
            task.completed = data['completed']

        task.updated_at = datetime.utcnow()
        db.session.commit()

        # Invalidate cache
        invalidate_cache()

        logger.info(f"Updated task: {task.id}")
        return jsonify(task.to_dict()), 200
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error updating task {task_id}: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/tasks/<int:task_id>', methods=['DELETE'])
def delete_task(task_id):
    """Delete a task"""
    try:
        task = Task.query.get_or_404(task_id)
        db.session.delete(task)
        db.session.commit()

        # Invalidate cache
        invalidate_cache()

        logger.info(f"Deleted task: {task_id}")
        return jsonify({'message': 'Task deleted successfully'}), 200
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error deleting task {task_id}: {str(e)}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
