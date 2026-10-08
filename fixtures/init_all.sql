-- ============================================================================
-- PostgreSQL MCP - All Demo Databases (single init script)
-- ============================================================================
-- Creates and seeds 6 databases used by pg-mcp:
--   blog_small, ecommerce_medium, saas_crm_large,
--   hr_system, hospital_care, security_ops
--
-- Usage (psql):
--   psql -h HOST -U USER -f init_all.sql
--
-- Or: python scripts/load_fixtures.py
-- ============================================================================


-- ============================================================================
-- DATABASE: blog_small
-- ============================================================================

DROP DATABASE IF EXISTS blog_small;
CREATE DATABASE blog_small;
\c blog_small

-- ============================================================================
-- CUSTOM TYPES
-- ============================================================================

-- User role enumeration
CREATE TYPE user_role AS ENUM ('admin', 'author', 'reader');

-- Post status enumeration
CREATE TYPE post_status AS ENUM ('draft', 'published', 'archived');

-- ============================================================================
-- TABLES
-- ============================================================================

-- Users table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    role user_role DEFAULT 'reader',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE users IS 'Blog users with role-based access';
COMMENT ON COLUMN users.role IS 'User role: admin, author, or reader';

-- Categories table
CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    slug VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE categories IS 'Blog post categories';

-- Posts table
CREATE TABLE posts (
    id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    slug VARCHAR(200) UNIQUE NOT NULL,
    content TEXT NOT NULL,
    excerpt TEXT,
    author_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
    status post_status DEFAULT 'draft',
    view_count INTEGER DEFAULT 0,
    published_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE posts IS 'Blog posts with authors and categories';
COMMENT ON COLUMN posts.status IS 'Post publication status';

-- Tags table
CREATE TABLE tags (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    slug VARCHAR(50) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE tags IS 'Tags for categorizing posts';

-- Post-Tag junction table
CREATE TABLE post_tags (
    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (post_id, tag_id)
);

COMMENT ON TABLE post_tags IS 'Many-to-many relationship between posts and tags';

-- Comments table
CREATE TABLE comments (
    id SERIAL PRIMARY KEY,
    post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id INTEGER REFERENCES comments(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE comments IS 'User comments on posts with threading support';
COMMENT ON COLUMN comments.parent_id IS 'Parent comment ID for nested replies';

-- User sessions table
CREATE TABLE user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    login_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    logout_time TIMESTAMP,
    ip_address INET,
    user_agent TEXT
);

COMMENT ON TABLE user_sessions IS 'User login session tracking';

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Users indexes
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_created_at ON users(created_at DESC);

-- Posts indexes
CREATE INDEX idx_posts_author_id ON posts(author_id);
CREATE INDEX idx_posts_category_id ON posts(category_id);
CREATE INDEX idx_posts_status ON posts(status);
CREATE INDEX idx_posts_published_at ON posts(published_at DESC) WHERE status = 'published';
CREATE INDEX idx_posts_created_at ON posts(created_at DESC);

-- Comments indexes
CREATE INDEX idx_comments_post_id ON comments(post_id);
CREATE INDEX idx_comments_user_id ON comments(user_id);
CREATE INDEX idx_comments_parent_id ON comments(parent_id);

-- Sessions indexes
CREATE INDEX idx_sessions_user_id ON user_sessions(user_id);
CREATE INDEX idx_sessions_login_time ON user_sessions(login_time DESC);

-- ============================================================================
-- VIEWS
-- ============================================================================

-- View: Published posts with author and category info
CREATE VIEW published_posts AS
SELECT
    p.id,
    p.title,
    p.slug,
    p.excerpt,
    p.view_count,
    p.published_at,
    u.username AS author_name,
    u.full_name AS author_full_name,
    c.name AS category_name,
    c.slug AS category_slug,
    COUNT(DISTINCT cm.id) AS comment_count
FROM posts p
JOIN users u ON p.author_id = u.id
LEFT JOIN categories c ON p.category_id = c.id
LEFT JOIN comments cm ON p.id = cm.post_id
WHERE p.status = 'published'
GROUP BY p.id, u.username, u.full_name, c.name, c.slug;

COMMENT ON VIEW published_posts IS 'Published posts with aggregated metadata';

-- View: User statistics
CREATE VIEW user_stats AS
SELECT
    u.id,
    u.username,
    u.full_name,
    u.role,
    COUNT(DISTINCT p.id) AS post_count,
    COUNT(DISTINCT c.id) AS comment_count,
    MAX(p.published_at) AS last_post_date,
    MAX(c.created_at) AS last_comment_date
FROM users u
LEFT JOIN posts p ON u.id = p.author_id AND p.status = 'published'
LEFT JOIN comments c ON u.id = c.user_id
GROUP BY u.id, u.username, u.full_name, u.role;

COMMENT ON VIEW user_stats IS 'User activity statistics';

-- View: Popular tags
CREATE VIEW popular_tags AS
SELECT
    t.id,
    t.name,
    t.slug,
    COUNT(pt.post_id) AS post_count,
    MAX(p.published_at) AS last_used_date
FROM tags t
LEFT JOIN post_tags pt ON t.id = pt.tag_id
LEFT JOIN posts p ON pt.post_id = p.id AND p.status = 'published'
GROUP BY t.id, t.name, t.slug
ORDER BY post_count DESC;

COMMENT ON VIEW popular_tags IS 'Tags sorted by usage frequency';

-- ============================================================================
-- SAMPLE DATA
-- ============================================================================

-- Insert users
INSERT INTO users (username, email, full_name, role) VALUES
('admin', 'admin@blog.com', 'Admin User', 'admin'),
('alice', 'alice@blog.com', 'Alice Johnson', 'author'),
('bob', 'bob@blog.com', 'Bob Smith', 'author'),
('charlie', 'charlie@blog.com', 'Charlie Brown', 'reader'),
('diana', 'diana@blog.com', 'Diana Prince', 'reader'),
('evan', 'evan@blog.com', 'Evan Williams', 'reader'),
('frank', 'frank@blog.com', 'Frank Miller', 'author'),
('grace', 'grace@blog.com', 'Grace Hopper', 'reader');

-- Insert categories
INSERT INTO categories (name, slug, description) VALUES
('Technology', 'technology', 'Articles about technology and programming'),
('Travel', 'travel', 'Travel guides and experiences'),
('Food', 'food', 'Recipes and restaurant reviews'),
('Lifestyle', 'lifestyle', 'Life tips and personal development'),
('Business', 'business', 'Business insights and entrepreneurship');

-- Insert tags
INSERT INTO tags (name, slug) VALUES
('Python', 'python'),
('JavaScript', 'javascript'),
('Tutorial', 'tutorial'),
('Review', 'review'),
('Guide', 'guide'),
('Opinion', 'opinion'),
('News', 'news'),
('Tips', 'tips');

-- Insert posts
INSERT INTO posts (title, slug, content, excerpt, author_id, category_id, status, view_count, published_at) VALUES
('Getting Started with Python', 'getting-started-with-python',
 'Python is a versatile programming language...',
 'Learn the basics of Python programming',
 2, 1, 'published', 1523, CURRENT_TIMESTAMP - INTERVAL '30 days'),

('Top 10 Travel Destinations in 2024', 'top-10-travel-destinations-2024',
 'Discover the most amazing places to visit...',
 'A curated list of must-visit places',
 3, 2, 'published', 2341, CURRENT_TIMESTAMP - INTERVAL '25 days'),

('Homemade Pizza Recipe', 'homemade-pizza-recipe',
 'Making pizza at home is easier than you think...',
 'Step-by-step guide to perfect homemade pizza',
 7, 3, 'published', 892, CURRENT_TIMESTAMP - INTERVAL '20 days'),

('Time Management Tips for Developers', 'time-management-tips-developers',
 'As a developer, managing your time effectively...',
 'Productivity tips for software developers',
 2, 4, 'published', 1654, CURRENT_TIMESTAMP - INTERVAL '15 days'),

('Starting Your Own Business', 'starting-your-own-business',
 'Entrepreneurship is a challenging but rewarding journey...',
 'Essential steps to launch your startup',
 3, 5, 'published', 743, CURRENT_TIMESTAMP - INTERVAL '10 days'),

('Advanced JavaScript Patterns', 'advanced-javascript-patterns',
 'Modern JavaScript offers powerful patterns...',
 'Design patterns in modern JavaScript',
 2, 1, 'draft', 0, NULL),

('Hidden Gems in Tokyo', 'hidden-gems-tokyo',
 'Beyond the typical tourist spots, Tokyo offers...',
 'Discover lesser-known attractions in Tokyo',
 3, 2, 'published', 1205, CURRENT_TIMESTAMP - INTERVAL '5 days'),

('Healthy Breakfast Ideas', 'healthy-breakfast-ideas',
 'Start your day right with these nutritious breakfast options...',
 'Quick and healthy breakfast recipes',
 7, 3, 'published', 567, CURRENT_TIMESTAMP - INTERVAL '3 days'),

('Mindfulness in Daily Life', 'mindfulness-daily-life',
 'Incorporating mindfulness into your routine...',
 'Practical mindfulness techniques',
 2, 4, 'archived', 2100, CURRENT_TIMESTAMP - INTERVAL '60 days'),

('Remote Work Best Practices', 'remote-work-best-practices',
 'Working from home requires different strategies...',
 'How to be productive working remotely',
 3, 5, 'published', 1876, CURRENT_TIMESTAMP - INTERVAL '2 days');

-- Insert post-tag relationships
INSERT INTO post_tags (post_id, tag_id) VALUES
(1, 1), (1, 3),  -- Python tutorial
(2, 4), (2, 5),  -- Travel review/guide
(3, 5), (3, 8),  -- Recipe guide/tips
(4, 8), (4, 6),  -- Tips/opinion
(5, 5), (5, 6),  -- Business guide/opinion
(6, 2), (6, 3),  -- JavaScript tutorial
(7, 4), (7, 5),  -- Travel review/guide
(8, 5), (8, 8),  -- Food guide/tips
(9, 6), (9, 8),  -- Lifestyle opinion/tips
(10, 6), (10, 8); -- Business opinion/tips

-- Insert comments
INSERT INTO comments (post_id, user_id, parent_id, content) VALUES
(1, 4, NULL, 'Great introduction to Python! Very helpful for beginners.'),
(1, 5, NULL, 'I have been looking for a tutorial like this. Thanks!'),
(1, 6, 1, 'I agree, this is the best Python tutorial I have found.'),
(2, 4, NULL, 'I visited 3 of these places last year. Highly recommend!'),
(2, 5, NULL, 'Adding these to my bucket list!'),
(3, 5, NULL, 'Tried this recipe yesterday. The pizza was delicious!'),
(3, 6, NULL, 'What type of flour do you recommend?'),
(3, 7, 6, 'I use bread flour for a chewier crust.'),
(4, 6, NULL, 'These tips really helped me stay focused. Thank you!'),
(4, 8, NULL, 'Time blocking has changed my life!'),
(5, 4, NULL, 'Very insightful article about entrepreneurship.'),
(7, 5, NULL, 'Tokyo is amazing! Thanks for these hidden spots.'),
(7, 4, 12, 'Have you been to the Nezu Museum? It is beautiful.'),
(8, 6, NULL, 'Love these breakfast ideas. Quick and healthy!'),
(10, 4, NULL, 'Remote work definitely requires discipline.'),
(10, 5, NULL, 'I struggle with work-life balance when working from home.'),
(10, 8, 15, 'Setting boundaries is key. I have a dedicated workspace now.');

-- Insert user sessions
INSERT INTO user_sessions (user_id, login_time, logout_time, ip_address) VALUES
(1, CURRENT_TIMESTAMP - INTERVAL '1 hour', CURRENT_TIMESTAMP - INTERVAL '30 minutes', '192.168.1.1'),
(2, CURRENT_TIMESTAMP - INTERVAL '2 hours', CURRENT_TIMESTAMP - INTERVAL '1 hour', '192.168.1.2'),
(3, CURRENT_TIMESTAMP - INTERVAL '3 hours', CURRENT_TIMESTAMP - INTERVAL '2 hours', '192.168.1.3'),
(4, CURRENT_TIMESTAMP - INTERVAL '4 hours', CURRENT_TIMESTAMP - INTERVAL '3 hours', '192.168.1.4'),
(5, CURRENT_TIMESTAMP - INTERVAL '5 hours', NULL, '192.168.1.5'),
(6, CURRENT_TIMESTAMP - INTERVAL '30 minutes', NULL, '192.168.1.6'),
(2, CURRENT_TIMESTAMP - INTERVAL '1 day', CURRENT_TIMESTAMP - INTERVAL '23 hours', '192.168.1.2'),
(3, CURRENT_TIMESTAMP - INTERVAL '2 days', CURRENT_TIMESTAMP - INTERVAL '1 day 23 hours', '192.168.1.3'),
(4, CURRENT_TIMESTAMP - INTERVAL '3 days', CURRENT_TIMESTAMP - INTERVAL '2 days 22 hours', '192.168.1.4');

-- ============================================================================
-- DATABASE STATISTICS
-- ============================================================================

-- Vacuum and analyze for optimal performance
VACUUM ANALYZE;

-- Display summary
SELECT
    'Database' AS object_type,
    current_database() AS name,
    'Small blog system with 7 tables, 3 views, 2 types' AS description
UNION ALL
SELECT
    'Tables' AS object_type,
    COUNT(*)::text AS name,
    'User-defined tables' AS description
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
UNION ALL
SELECT
    'Views' AS object_type,
    COUNT(*)::text AS name,
    'User-defined views' AS description
FROM information_schema.views
WHERE table_schema = 'public'
UNION ALL
SELECT
    'Data Rows' AS object_type,
    SUM(n_live_tup)::text AS name,
    'Total rows across all tables' AS description
FROM pg_stat_user_tables;

-- ============================================================================
-- DATABASE: ecommerce_medium
-- ============================================================================

DROP DATABASE IF EXISTS ecommerce_medium;
CREATE DATABASE ecommerce_medium;
\c ecommerce_medium

-- ============================================================================
-- CUSTOM TYPES
-- ============================================================================

CREATE TYPE user_status AS ENUM ('active', 'inactive', 'suspended', 'deleted');
CREATE TYPE order_status AS ENUM ('pending', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded');
CREATE TYPE payment_status AS ENUM ('pending', 'completed', 'failed', 'refunded');
CREATE TYPE payment_method AS ENUM ('credit_card', 'debit_card', 'paypal', 'bank_transfer', 'cash_on_delivery');

-- ============================================================================
-- CORE TABLES - USERS & AUTHENTICATION
-- ============================================================================

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    status user_status DEFAULT 'active',
    email_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP
);

COMMENT ON TABLE users IS 'Customer accounts';

CREATE TABLE user_addresses (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    address_type VARCHAR(20) DEFAULT 'shipping',
    street_address VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100),
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(100) NOT NULL,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE user_addresses IS 'User shipping and billing addresses';

CREATE TABLE user_profiles (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    avatar_url VARCHAR(500),
    date_of_birth DATE,
    gender VARCHAR(20),
    bio TEXT,
    preferences JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE user_profiles IS 'Extended user profile information';

-- ============================================================================
-- PRODUCT CATALOG
-- ============================================================================

CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    parent_id INTEGER REFERENCES categories(id) ON DELETE CASCADE,
    description TEXT,
    image_url VARCHAR(500),
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE categories IS 'Product categories with hierarchical structure';

CREATE TABLE brands (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    logo_url VARCHAR(500),
    website VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE brands IS 'Product brands/manufacturers';

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    sku VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    brand_id INTEGER REFERENCES brands(id) ON DELETE SET NULL,
    category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
    price DECIMAL(10, 2) NOT NULL,
    compare_at_price DECIMAL(10, 2),
    cost_price DECIMAL(10, 2),
    is_active BOOLEAN DEFAULT TRUE,
    is_featured BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE products IS 'Product catalog';

CREATE TABLE product_images (
    id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    image_url VARCHAR(500) NOT NULL,
    alt_text VARCHAR(255),
    display_order INTEGER DEFAULT 0,
    is_primary BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE product_images IS 'Product image gallery';

CREATE TABLE product_variants (
    id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    sku VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10, 2),
    attributes JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE product_variants IS 'Product variants (size, color, etc.)';

-- ============================================================================
-- INVENTORY MANAGEMENT
-- ============================================================================

CREATE TABLE warehouses (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    code VARCHAR(50) UNIQUE NOT NULL,
    address VARCHAR(255),
    city VARCHAR(100),
    state VARCHAR(100),
    country VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE warehouses IS 'Warehouse locations';

CREATE TABLE inventory (
    id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    warehouse_id INTEGER NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL DEFAULT 0,
    reserved_quantity INTEGER NOT NULL DEFAULT 0,
    reorder_point INTEGER DEFAULT 10,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(product_id, warehouse_id)
);

COMMENT ON TABLE inventory IS 'Product inventory levels by warehouse';

CREATE TABLE inventory_transactions (
    id SERIAL PRIMARY KEY,
    inventory_id INTEGER NOT NULL REFERENCES inventory(id) ON DELETE CASCADE,
    transaction_type VARCHAR(50) NOT NULL,
    quantity INTEGER NOT NULL,
    reference_type VARCHAR(50),
    reference_id INTEGER,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE inventory_transactions IS 'Inventory movement history';

-- ============================================================================
-- SHOPPING CART
-- ============================================================================

CREATE TABLE carts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    session_id VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP
);

COMMENT ON TABLE carts IS 'Shopping carts for registered and guest users';

CREATE TABLE cart_items (
    id SERIAL PRIMARY KEY,
    cart_id INTEGER NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    variant_id INTEGER REFERENCES product_variants(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL DEFAULT 1,
    price DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE cart_items IS 'Items in shopping carts';

-- ============================================================================
-- ORDERS & PAYMENTS
-- ============================================================================

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    order_number VARCHAR(50) UNIQUE NOT NULL,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status order_status DEFAULT 'pending',
    subtotal DECIMAL(10, 2) NOT NULL,
    tax_amount DECIMAL(10, 2) DEFAULT 0,
    shipping_amount DECIMAL(10, 2) DEFAULT 0,
    discount_amount DECIMAL(10, 2) DEFAULT 0,
    total_amount DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    shipping_address_id INTEGER REFERENCES user_addresses(id),
    billing_address_id INTEGER REFERENCES user_addresses(id),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP
);

COMMENT ON TABLE orders IS 'Customer orders';

CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    variant_id INTEGER REFERENCES product_variants(id),
    product_name VARCHAR(255) NOT NULL,
    sku VARCHAR(100) NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL,
    total_price DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE order_items IS 'Line items in orders';

CREATE TABLE payments (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    payment_method payment_method NOT NULL,
    status payment_status DEFAULT 'pending',
    amount DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    transaction_id VARCHAR(255),
    payment_gateway VARCHAR(100),
    payment_details JSONB,
    processed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE payments IS 'Payment transactions';

-- ============================================================================
-- SHIPPING & FULFILLMENT
-- ============================================================================

CREATE TABLE shipping_carriers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    code VARCHAR(50) UNIQUE NOT NULL,
    website VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE shipping_carriers IS 'Shipping carrier companies';

CREATE TABLE shipments (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    carrier_id INTEGER REFERENCES shipping_carriers(id),
    tracking_number VARCHAR(255),
    warehouse_id INTEGER REFERENCES warehouses(id),
    status VARCHAR(50) DEFAULT 'pending',
    shipped_at TIMESTAMP,
    estimated_delivery TIMESTAMP,
    delivered_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE shipments IS 'Order shipment tracking';

-- ============================================================================
-- PROMOTIONS & DISCOUNTS
-- ============================================================================

CREATE TABLE coupons (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    discount_type VARCHAR(20) NOT NULL,
    discount_value DECIMAL(10, 2) NOT NULL,
    min_order_amount DECIMAL(10, 2),
    max_discount_amount DECIMAL(10, 2),
    usage_limit INTEGER,
    usage_count INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    starts_at TIMESTAMP,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE coupons IS 'Discount coupons and promo codes';

CREATE TABLE coupon_usage (
    id SERIAL PRIMARY KEY,
    coupon_id INTEGER NOT NULL REFERENCES coupons(id) ON DELETE CASCADE,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    discount_amount DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(coupon_id, order_id)
);

COMMENT ON TABLE coupon_usage IS 'Coupon redemption history';

-- ============================================================================
-- REVIEWS & RATINGS
-- ============================================================================

CREATE TABLE product_reviews (
    id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    order_id INTEGER REFERENCES orders(id) ON DELETE SET NULL,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    title VARCHAR(255),
    comment TEXT,
    is_verified_purchase BOOLEAN DEFAULT FALSE,
    is_approved BOOLEAN DEFAULT FALSE,
    helpful_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(product_id, user_id, order_id)
);

COMMENT ON TABLE product_reviews IS 'Customer product reviews and ratings';

CREATE TABLE review_votes (
    id SERIAL PRIMARY KEY,
    review_id INTEGER NOT NULL REFERENCES product_reviews(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_helpful BOOLEAN NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(review_id, user_id)
);

COMMENT ON TABLE review_votes IS 'User votes on review helpfulness';

-- ============================================================================
-- WISHLISTS
-- ============================================================================

CREATE TABLE wishlists (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) DEFAULT 'My Wishlist',
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE wishlists IS 'User wishlists';

CREATE TABLE wishlist_items (
    id SERIAL PRIMARY KEY,
    wishlist_id INTEGER NOT NULL REFERENCES wishlists(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(wishlist_id, product_id)
);

COMMENT ON TABLE wishlist_items IS 'Products in wishlists';

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Users indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_created_at ON users(created_at DESC);

-- Addresses indexes
CREATE INDEX idx_addresses_user_id ON user_addresses(user_id);
CREATE INDEX idx_addresses_is_default ON user_addresses(user_id, is_default);

-- Categories indexes
CREATE INDEX idx_categories_parent_id ON categories(parent_id);
CREATE INDEX idx_categories_is_active ON categories(is_active);

-- Products indexes
CREATE INDEX idx_products_category_id ON products(category_id);
CREATE INDEX idx_products_brand_id ON products(brand_id);
CREATE INDEX idx_products_is_active ON products(is_active);
CREATE INDEX idx_products_is_featured ON products(is_featured) WHERE is_featured = TRUE;
CREATE INDEX idx_products_price ON products(price);
CREATE INDEX idx_products_created_at ON products(created_at DESC);

-- Product images indexes
CREATE INDEX idx_product_images_product_id ON product_images(product_id);

-- Product variants indexes
CREATE INDEX idx_product_variants_product_id ON product_variants(product_id);

-- Inventory indexes
CREATE INDEX idx_inventory_product_id ON inventory(product_id);
CREATE INDEX idx_inventory_warehouse_id ON inventory(warehouse_id);
CREATE INDEX idx_inventory_low_stock ON inventory(product_id) WHERE quantity <= reorder_point;

-- Inventory transactions indexes
CREATE INDEX idx_inventory_txn_inventory_id ON inventory_transactions(inventory_id);
CREATE INDEX idx_inventory_txn_created_at ON inventory_transactions(created_at DESC);

-- Cart indexes
CREATE INDEX idx_carts_user_id ON carts(user_id);
CREATE INDEX idx_carts_session_id ON carts(session_id);

-- Cart items indexes
CREATE INDEX idx_cart_items_cart_id ON cart_items(cart_id);
CREATE INDEX idx_cart_items_product_id ON cart_items(product_id);

-- Orders indexes
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);
CREATE INDEX idx_orders_order_number ON orders(order_number);

-- Order items indexes
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);

-- Payments indexes
CREATE INDEX idx_payments_order_id ON payments(order_id);
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_payments_created_at ON payments(created_at DESC);

-- Shipments indexes
CREATE INDEX idx_shipments_order_id ON shipments(order_id);
CREATE INDEX idx_shipments_status ON shipments(status);
CREATE INDEX idx_shipments_tracking_number ON shipments(tracking_number);

-- Coupons indexes
CREATE INDEX idx_coupons_code ON coupons(code);
CREATE INDEX idx_coupons_is_active ON coupons(is_active) WHERE is_active = TRUE;

-- Reviews indexes
CREATE INDEX idx_reviews_product_id ON product_reviews(product_id);
CREATE INDEX idx_reviews_user_id ON product_reviews(user_id);
CREATE INDEX idx_reviews_is_approved ON product_reviews(is_approved) WHERE is_approved = TRUE;
CREATE INDEX idx_reviews_rating ON product_reviews(rating);

-- Wishlist indexes
CREATE INDEX idx_wishlists_user_id ON wishlists(user_id);
CREATE INDEX idx_wishlist_items_wishlist_id ON wishlist_items(wishlist_id);

-- ============================================================================
-- VIEWS
-- ============================================================================

-- Active products with inventory
CREATE VIEW active_products_inventory AS
SELECT
    p.id,
    p.name,
    p.sku,
    p.price,
    p.compare_at_price,
    c.name AS category_name,
    b.name AS brand_name,
    COALESCE(SUM(i.quantity), 0) AS total_stock,
    COALESCE(SUM(i.reserved_quantity), 0) AS reserved_stock,
    COALESCE(SUM(i.quantity - i.reserved_quantity), 0) AS available_stock
FROM products p
LEFT JOIN categories c ON p.category_id = c.id
LEFT JOIN brands b ON p.brand_id = b.id
LEFT JOIN inventory i ON p.id = i.product_id
WHERE p.is_active = TRUE
GROUP BY p.id, p.name, p.sku, p.price, p.compare_at_price, c.name, b.name;

COMMENT ON VIEW active_products_inventory IS 'Active products with aggregated inventory';

-- Product ratings summary
CREATE VIEW product_ratings AS
SELECT
    p.id AS product_id,
    p.name AS product_name,
    COUNT(r.id) AS review_count,
    AVG(r.rating)::NUMERIC(3,2) AS average_rating,
    COUNT(CASE WHEN r.rating = 5 THEN 1 END) AS five_star_count,
    COUNT(CASE WHEN r.rating = 4 THEN 1 END) AS four_star_count,
    COUNT(CASE WHEN r.rating = 3 THEN 1 END) AS three_star_count,
    COUNT(CASE WHEN r.rating = 2 THEN 1 END) AS two_star_count,
    COUNT(CASE WHEN r.rating = 1 THEN 1 END) AS one_star_count
FROM products p
LEFT JOIN product_reviews r ON p.id = r.product_id AND r.is_approved = TRUE
GROUP BY p.id, p.name;

COMMENT ON VIEW product_ratings IS 'Product review statistics';

-- Customer order history
CREATE VIEW customer_order_summary AS
SELECT
    u.id AS user_id,
    u.email,
    u.first_name,
    u.last_name,
    COUNT(o.id) AS total_orders,
    SUM(CASE WHEN o.status = 'delivered' THEN o.total_amount ELSE 0 END) AS total_spent,
    MAX(o.created_at) AS last_order_date,
    AVG(o.total_amount)::NUMERIC(10,2) AS average_order_value
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.email, u.first_name, u.last_name;

COMMENT ON VIEW customer_order_summary IS 'Customer purchase statistics';

-- Order details with items
CREATE VIEW order_details AS
SELECT
    o.id AS order_id,
    o.order_number,
    o.status,
    o.total_amount,
    o.created_at,
    u.email AS customer_email,
    u.first_name || ' ' || u.last_name AS customer_name,
    COUNT(oi.id) AS item_count,
    STRING_AGG(oi.product_name, ', ') AS products
FROM orders o
JOIN users u ON o.user_id = u.id
LEFT JOIN order_items oi ON o.id = oi.order_id
GROUP BY o.id, o.order_number, o.status, o.total_amount, o.created_at, u.email, u.first_name, u.last_name;

COMMENT ON VIEW order_details IS 'Order summary with customer info';

-- Low stock products
CREATE VIEW low_stock_products AS
SELECT
    p.id,
    p.name,
    p.sku,
    w.name AS warehouse_name,
    i.quantity AS current_stock,
    i.reserved_quantity,
    i.reorder_point,
    (i.quantity - i.reserved_quantity) AS available_stock
FROM inventory i
JOIN products p ON i.product_id = p.id
JOIN warehouses w ON i.warehouse_id = w.id
WHERE i.quantity <= i.reorder_point
ORDER BY (i.quantity - i.reorder_point);

COMMENT ON VIEW low_stock_products IS 'Products below reorder point';

-- Daily sales summary
CREATE VIEW daily_sales AS
SELECT
    DATE(created_at) AS sale_date,
    COUNT(*) AS order_count,
    SUM(total_amount) AS total_revenue,
    AVG(total_amount)::NUMERIC(10,2) AS average_order_value,
    COUNT(DISTINCT user_id) AS unique_customers
FROM orders
WHERE status NOT IN ('cancelled', 'refunded')
GROUP BY DATE(created_at)
ORDER BY sale_date DESC;

COMMENT ON VIEW daily_sales IS 'Daily sales metrics';

-- ============================================================================
-- SAMPLE DATA
-- ============================================================================

-- Insert users
INSERT INTO users (email, password_hash, first_name, last_name, phone, status, email_verified) VALUES
('john.doe@email.com', '$2b$10$hash1', 'John', 'Doe', '+1234567890', 'active', TRUE),
('jane.smith@email.com', '$2b$10$hash2', 'Jane', 'Smith', '+1234567891', 'active', TRUE),
('bob.johnson@email.com', '$2b$10$hash3', 'Bob', 'Johnson', '+1234567892', 'active', TRUE),
('alice.williams@email.com', '$2b$10$hash4', 'Alice', 'Williams', '+1234567893', 'active', TRUE),
('charlie.brown@email.com', '$2b$10$hash5', 'Charlie', 'Brown', '+1234567894', 'active', FALSE),
('diana.prince@email.com', '$2b$10$hash6', 'Diana', 'Prince', '+1234567895', 'active', TRUE),
('evan.hansen@email.com', '$2b$10$hash7', 'Evan', 'Hansen', '+1234567896', 'inactive', TRUE),
('frank.miller@email.com', '$2b$10$hash8', 'Frank', 'Miller', '+1234567897', 'active', TRUE),
('grace.hopper@email.com', '$2b$10$hash9', 'Grace', 'Hopper', '+1234567898', 'active', TRUE),
('henry.ford@email.com', '$2b$10$hash10', 'Henry', 'Ford', '+1234567899', 'active', TRUE);

-- Insert addresses
INSERT INTO user_addresses (user_id, address_type, street_address, city, state, postal_code, country, is_default) VALUES
(1, 'shipping', '123 Main St', 'New York', 'NY', '10001', 'USA', TRUE),
(1, 'billing', '123 Main St', 'New York', 'NY', '10001', 'USA', FALSE),
(2, 'shipping', '456 Oak Ave', 'Los Angeles', 'CA', '90001', 'USA', TRUE),
(3, 'shipping', '789 Pine Rd', 'Chicago', 'IL', '60601', 'USA', TRUE),
(4, 'shipping', '321 Elm St', 'Houston', 'TX', '77001', 'USA', TRUE),
(5, 'shipping', '654 Maple Dr', 'Phoenix', 'AZ', '85001', 'USA', TRUE),
(6, 'shipping', '987 Cedar Ln', 'Philadelphia', 'PA', '19101', 'USA', TRUE);

-- Insert categories
INSERT INTO categories (name, slug, parent_id, description, display_order, is_active) VALUES
('Electronics', 'electronics', NULL, 'Electronic devices and accessories', 1, TRUE),
('Computers', 'computers', 1, 'Laptops, desktops, and accessories', 1, TRUE),
('Smartphones', 'smartphones', 1, 'Mobile phones and accessories', 2, TRUE),
('Home & Garden', 'home-garden', NULL, 'Home improvement and garden supplies', 2, TRUE),
('Furniture', 'furniture', 4, 'Home and office furniture', 1, TRUE),
('Clothing', 'clothing', NULL, 'Apparel and fashion', 3, TRUE),
('Men', 'men', 6, 'Mens clothing', 1, TRUE),
('Women', 'women', 6, 'Womens clothing', 2, TRUE),
('Sports', 'sports', NULL, 'Sports and outdoor equipment', 4, TRUE),
('Books', 'books', NULL, 'Books and media', 5, TRUE);

-- Insert brands
INSERT INTO brands (name, slug, description, website) VALUES
('TechPro', 'techpro', 'Premium electronics brand', 'https://techpro.example.com'),
('HomeComfort', 'homecomfort', 'Quality home furnishings', 'https://homecomfort.example.com'),
('StyleWear', 'stylewear', 'Modern fashion brand', 'https://stylewear.example.com'),
('ActiveLife', 'activelife', 'Sports and fitness gear', 'https://activelife.example.com'),
('BookHaven', 'bookhaven', 'Publisher and book distributor', 'https://bookhaven.example.com');

-- Insert warehouses
INSERT INTO warehouses (name, code, address, city, state, country) VALUES
('East Coast Warehouse', 'EC-WH-01', '100 Industrial Pkwy', 'Newark', 'NJ', 'USA'),
('West Coast Warehouse', 'WC-WH-01', '200 Logistics Blvd', 'San Diego', 'CA', 'USA'),
('Central Warehouse', 'CT-WH-01', '300 Distribution Dr', 'Dallas', 'TX', 'USA');

-- Insert products
INSERT INTO products (name, slug, sku, description, brand_id, category_id, price, compare_at_price, cost_price, is_active, is_featured) VALUES
('Laptop Pro 15', 'laptop-pro-15', 'TECH-LP-001', 'High-performance laptop for professionals', 1, 2, 1299.99, 1499.99, 800.00, TRUE, TRUE),
('Smartphone X', 'smartphone-x', 'TECH-SP-001', 'Latest flagship smartphone', 1, 3, 899.99, 999.99, 600.00, TRUE, TRUE),
('Wireless Mouse', 'wireless-mouse', 'TECH-MS-001', 'Ergonomic wireless mouse', 1, 2, 29.99, 39.99, 15.00, TRUE, FALSE),
('Office Chair Deluxe', 'office-chair-deluxe', 'HOME-CH-001', 'Comfortable ergonomic office chair', 2, 5, 299.99, 349.99, 150.00, TRUE, TRUE),
('Desk Lamp LED', 'desk-lamp-led', 'HOME-LM-001', 'Modern LED desk lamp', 2, 5, 49.99, 59.99, 25.00, TRUE, FALSE),
('Running Shoes Pro', 'running-shoes-pro', 'SPORT-SH-001', 'Professional running shoes', 4, 9, 129.99, 149.99, 60.00, TRUE, TRUE),
('Yoga Mat Premium', 'yoga-mat-premium', 'SPORT-YM-001', 'Non-slip premium yoga mat', 4, 9, 39.99, 49.99, 20.00, TRUE, FALSE),
('Mens T-Shirt Classic', 'mens-tshirt-classic', 'STYLE-MT-001', 'Classic cotton t-shirt', 3, 7, 24.99, 29.99, 10.00, TRUE, FALSE),
('Womens Jeans', 'womens-jeans', 'STYLE-WJ-001', 'Comfortable slim-fit jeans', 3, 8, 79.99, 89.99, 35.00, TRUE, FALSE),
('Programming Guide', 'programming-guide', 'BOOK-PG-001', 'Complete programming reference', 5, 10, 49.99, NULL, 20.00, TRUE, FALSE),
('Tablet 10 inch', 'tablet-10-inch', 'TECH-TB-001', 'Portable tablet device', 1, 1, 399.99, 449.99, 250.00, TRUE, FALSE),
('USB-C Cable', 'usb-c-cable', 'TECH-CB-001', 'Fast charging USB-C cable', 1, 1, 14.99, 19.99, 5.00, TRUE, FALSE),
('Coffee Table Oak', 'coffee-table-oak', 'HOME-CT-001', 'Solid oak coffee table', 2, 5, 249.99, 299.99, 120.00, TRUE, FALSE),
('Garden Tools Set', 'garden-tools-set', 'HOME-GT-001', 'Complete garden tool kit', 2, 4, 89.99, 99.99, 40.00, TRUE, FALSE),
('Backpack Hiking', 'backpack-hiking', 'SPORT-BP-001', 'Durable hiking backpack', 4, 9, 69.99, 79.99, 30.00, TRUE, FALSE);

-- Insert product images
INSERT INTO product_images (product_id, image_url, alt_text, display_order, is_primary) VALUES
(1, 'https://images.example.com/laptop-pro-15-1.jpg', 'Laptop Pro 15 Front View', 1, TRUE),
(1, 'https://images.example.com/laptop-pro-15-2.jpg', 'Laptop Pro 15 Side View', 2, FALSE),
(2, 'https://images.example.com/smartphone-x-1.jpg', 'Smartphone X Front', 1, TRUE),
(3, 'https://images.example.com/wireless-mouse-1.jpg', 'Wireless Mouse', 1, TRUE),
(4, 'https://images.example.com/office-chair-1.jpg', 'Office Chair Deluxe', 1, TRUE);

-- Insert inventory
INSERT INTO inventory (product_id, warehouse_id, quantity, reserved_quantity, reorder_point) VALUES
(1, 1, 50, 5, 10),
(1, 2, 45, 3, 10),
(2, 1, 100, 10, 20),
(2, 2, 95, 8, 20),
(3, 1, 200, 15, 30),
(4, 1, 30, 2, 5),
(4, 3, 25, 1, 5),
(5, 1, 80, 5, 15),
(6, 2, 120, 10, 25),
(7, 1, 150, 12, 30),
(8, 1, 300, 20, 50),
(9, 1, 180, 15, 40),
(10, 1, 75, 5, 15),
(11, 2, 60, 4, 10),
(12, 1, 500, 30, 100),
(13, 3, 20, 1, 5),
(14, 1, 40, 3, 10),
(15, 2, 70, 5, 15);

-- Insert shipping carriers
INSERT INTO shipping_carriers (name, code, website) VALUES
('FedEx', 'FEDEX', 'https://www.fedex.com'),
('UPS', 'UPS', 'https://www.ups.com'),
('USPS', 'USPS', 'https://www.usps.com'),
('DHL', 'DHL', 'https://www.dhl.com');

-- Insert coupons
INSERT INTO coupons (code, description, discount_type, discount_value, min_order_amount, usage_limit, is_active, starts_at, expires_at) VALUES
('WELCOME10', '10% off first order', 'percentage', 10.00, 50.00, 1000, TRUE, CURRENT_TIMESTAMP - INTERVAL '30 days', CURRENT_TIMESTAMP + INTERVAL '30 days'),
('SAVE20', '$20 off orders over $100', 'fixed', 20.00, 100.00, 500, TRUE, CURRENT_TIMESTAMP - INTERVAL '15 days', CURRENT_TIMESTAMP + INTERVAL '45 days'),
('FREESHIP', 'Free shipping', 'fixed', 10.00, 75.00, NULL, TRUE, CURRENT_TIMESTAMP - INTERVAL '10 days', CURRENT_TIMESTAMP + INTERVAL '60 days');

-- Insert orders
INSERT INTO orders (order_number, user_id, status, subtotal, tax_amount, shipping_amount, discount_amount, total_amount, shipping_address_id, billing_address_id, created_at, completed_at) VALUES
('ORD-2024-0001', 1, 'delivered', 1329.98, 106.40, 10.00, 0.00, 1446.38, 1, 2, CURRENT_TIMESTAMP - INTERVAL '30 days', CURRENT_TIMESTAMP - INTERVAL '25 days'),
('ORD-2024-0002', 2, 'delivered', 899.99, 72.00, 10.00, 89.90, 892.09, 3, 3, CURRENT_TIMESTAMP - INTERVAL '28 days', CURRENT_TIMESTAMP - INTERVAL '23 days'),
('ORD-2024-0003', 3, 'delivered', 329.98, 26.40, 10.00, 0.00, 366.38, 4, 4, CURRENT_TIMESTAMP - INTERVAL '25 days', CURRENT_TIMESTAMP - INTERVAL '20 days'),
('ORD-2024-0004', 1, 'shipped', 179.97, 14.40, 10.00, 0.00, 204.37, 1, 2, CURRENT_TIMESTAMP - INTERVAL '5 days', NULL),
('ORD-2024-0005', 4, 'processing', 549.98, 44.00, 10.00, 20.00, 583.98, 5, 5, CURRENT_TIMESTAMP - INTERVAL '3 days', NULL),
('ORD-2024-0006', 5, 'pending', 129.99, 10.40, 10.00, 12.99, 137.40, 6, 6, CURRENT_TIMESTAMP - INTERVAL '1 day', NULL),
('ORD-2024-0007', 6, 'cancelled', 299.99, 24.00, 10.00, 0.00, 333.99, 7, 7, CURRENT_TIMESTAMP - INTERVAL '10 days', NULL);

-- Insert order items
INSERT INTO order_items (order_id, product_id, product_name, sku, quantity, unit_price, total_price) VALUES
(1, 1, 'Laptop Pro 15', 'TECH-LP-001', 1, 1299.99, 1299.99),
(1, 3, 'Wireless Mouse', 'TECH-MS-001', 1, 29.99, 29.99),
(2, 2, 'Smartphone X', 'TECH-SP-001', 1, 899.99, 899.99),
(3, 4, 'Office Chair Deluxe', 'HOME-CH-001', 1, 299.99, 299.99),
(3, 3, 'Wireless Mouse', 'TECH-MS-001', 1, 29.99, 29.99),
(4, 6, 'Running Shoes Pro', 'SPORT-SH-001', 1, 129.99, 129.99),
(4, 7, 'Yoga Mat Premium', 'SPORT-YM-001', 1, 39.99, 39.99),
(4, 12, 'USB-C Cable', 'TECH-CB-001', 1, 14.99, 14.99),
(5, 4, 'Office Chair Deluxe', 'HOME-CH-001', 1, 299.99, 299.99),
(5, 13, 'Coffee Table Oak', 'HOME-CT-001', 1, 249.99, 249.99),
(6, 6, 'Running Shoes Pro', 'SPORT-SH-001', 1, 129.99, 129.99),
(7, 4, 'Office Chair Deluxe', 'HOME-CH-001', 1, 299.99, 299.99);

-- Insert payments
INSERT INTO payments (order_id, payment_method, status, amount, transaction_id, payment_gateway, processed_at) VALUES
(1, 'credit_card', 'completed', 1446.38, 'txn_001', 'Stripe', CURRENT_TIMESTAMP - INTERVAL '30 days'),
(2, 'paypal', 'completed', 892.09, 'txn_002', 'PayPal', CURRENT_TIMESTAMP - INTERVAL '28 days'),
(3, 'credit_card', 'completed', 366.38, 'txn_003', 'Stripe', CURRENT_TIMESTAMP - INTERVAL '25 days'),
(4, 'credit_card', 'completed', 204.37, 'txn_004', 'Stripe', CURRENT_TIMESTAMP - INTERVAL '5 days'),
(5, 'debit_card', 'completed', 583.98, 'txn_005', 'Stripe', CURRENT_TIMESTAMP - INTERVAL '3 days'),
(6, 'credit_card', 'pending', 137.40, NULL, 'Stripe', NULL),
(7, 'credit_card', 'refunded', 333.99, 'txn_007', 'Stripe', CURRENT_TIMESTAMP - INTERVAL '10 days');

-- Insert shipments
INSERT INTO shipments (order_id, carrier_id, tracking_number, warehouse_id, status, shipped_at, estimated_delivery, delivered_at) VALUES
(1, 1, 'FDX123456789', 1, 'delivered', CURRENT_TIMESTAMP - INTERVAL '29 days', CURRENT_TIMESTAMP - INTERVAL '25 days', CURRENT_TIMESTAMP - INTERVAL '25 days'),
(2, 2, 'UPS987654321', 1, 'delivered', CURRENT_TIMESTAMP - INTERVAL '27 days', CURRENT_TIMESTAMP - INTERVAL '23 days', CURRENT_TIMESTAMP - INTERVAL '23 days'),
(3, 1, 'FDX111222333', 1, 'delivered', CURRENT_TIMESTAMP - INTERVAL '24 days', CURRENT_TIMESTAMP - INTERVAL '20 days', CURRENT_TIMESTAMP - INTERVAL '20 days'),
(4, 3, 'USPS444555666', 1, 'in_transit', CURRENT_TIMESTAMP - INTERVAL '4 days', CURRENT_TIMESTAMP + INTERVAL '1 day', NULL);

-- Insert product reviews
INSERT INTO product_reviews (product_id, user_id, order_id, rating, title, comment, is_verified_purchase, is_approved, helpful_count) VALUES
(1, 1, 1, 5, 'Excellent laptop!', 'This laptop exceeded my expectations. Fast, reliable, and great build quality.', TRUE, TRUE, 15),
(3, 1, 1, 4, 'Good mouse', 'Comfortable and responsive. Battery life could be better.', TRUE, TRUE, 8),
(2, 2, 2, 5, 'Best phone ever', 'Amazing camera quality and battery life. Highly recommend!', TRUE, TRUE, 23),
(4, 3, 3, 5, 'Super comfortable', 'My back pain is gone after using this chair. Worth every penny.', TRUE, TRUE, 12),
(3, 3, 3, 3, 'Average mouse', 'Works fine but nothing special. Expected more for the price.', TRUE, TRUE, 5),
(6, 1, 4, 5, 'Perfect running shoes', 'Great cushioning and support. My new favorite running shoes.', TRUE, TRUE, 9),
(7, 1, 4, 4, 'Good yoga mat', 'Non-slip surface works well. A bit thin for my preference.', TRUE, TRUE, 4);

-- Insert wishlists
INSERT INTO wishlists (user_id, name, is_public) VALUES
(1, 'My Wishlist', FALSE),
(2, 'Tech Wishlist', TRUE),
(3, 'Home Office Setup', FALSE);

-- Insert wishlist items
INSERT INTO wishlist_items (wishlist_id, product_id) VALUES
(1, 11), (1, 13), (1, 15),
(2, 1), (2, 2),
(3, 4), (3, 5), (3, 13);

-- ============================================================================
-- DATABASE STATISTICS
-- ============================================================================

VACUUM ANALYZE;

SELECT
    'Database' AS object_type,
    current_database() AS name,
    'E-commerce platform with 25 tables, 6 views, 4 types' AS description
UNION ALL
SELECT
    'Tables' AS object_type,
    COUNT(*)::text AS name,
    'User-defined tables' AS description
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
UNION ALL
SELECT
    'Views' AS object_type,
    COUNT(*)::text AS name,
    'User-defined views' AS description
FROM information_schema.views
WHERE table_schema = 'public';

-- ============================================================================
-- DATABASE: saas_crm_large
-- ============================================================================

DROP DATABASE IF EXISTS saas_crm_large;
CREATE DATABASE saas_crm_large;
\c saas_crm_large

-- ============================================================================
-- EXTENSIONS
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For fuzzy text search

-- ============================================================================
-- CUSTOM TYPES
-- ============================================================================

CREATE TYPE user_role AS ENUM ('owner', 'admin', 'manager', 'sales_rep', 'support_agent', 'viewer');
CREATE TYPE account_status AS ENUM ('trial', 'active', 'suspended', 'cancelled', 'expired');
CREATE TYPE subscription_status AS ENUM ('active', 'cancelled', 'past_due', 'unpaid', 'trialing');
CREATE TYPE lead_status AS ENUM ('new', 'contacted', 'qualified', 'unqualified', 'lost');
CREATE TYPE deal_stage AS ENUM ('prospecting', 'qualification', 'proposal', 'negotiation', 'closed_won', 'closed_lost');
CREATE TYPE ticket_status AS ENUM ('open', 'pending', 'in_progress', 'waiting_customer', 'resolved', 'closed');
CREATE TYPE ticket_priority AS ENUM ('low', 'medium', 'high', 'urgent');
CREATE TYPE task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
CREATE TYPE invoice_status AS ENUM ('draft', 'sent', 'paid', 'overdue', 'void', 'refunded');
CREATE TYPE payment_status AS ENUM ('pending', 'completed', 'failed', 'refunded');
CREATE TYPE activity_type AS ENUM ('call', 'email', 'meeting', 'note', 'task');
CREATE TYPE campaign_status AS ENUM ('draft', 'scheduled', 'active', 'paused', 'completed');

-- ============================================================================
-- MULTI-TENANT FOUNDATION
-- ============================================================================

CREATE TABLE organizations (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    domain VARCHAR(255),
    account_status account_status DEFAULT 'trial',
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    trial_ends_at TIMESTAMP,
    suspended_at TIMESTAMP,
    cancelled_at TIMESTAMP
);

COMMENT ON TABLE organizations IS 'Tenant organizations in multi-tenant system';

CREATE TABLE organization_settings (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER UNIQUE NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    timezone VARCHAR(100) DEFAULT 'UTC',
    currency VARCHAR(3) DEFAULT 'USD',
    date_format VARCHAR(50) DEFAULT 'YYYY-MM-DD',
    time_format VARCHAR(50) DEFAULT 'HH:mm:ss',
    language VARCHAR(10) DEFAULT 'en',
    business_hours JSONB,
    features JSONB DEFAULT '{}',
    limits JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE organization_settings IS 'Organization-specific configuration';

-- ============================================================================
-- USERS & AUTHENTICATION
-- ============================================================================

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    avatar_url VARCHAR(500),
    role user_role DEFAULT 'viewer',
    is_active BOOLEAN DEFAULT TRUE,
    email_verified BOOLEAN DEFAULT FALSE,
    two_factor_enabled BOOLEAN DEFAULT FALSE,
    last_login TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(organization_id, email)
);

COMMENT ON TABLE users IS 'Users with organization membership';

CREATE TABLE user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_token VARCHAR(255) UNIQUE NOT NULL,
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE user_sessions IS 'Active user sessions';

CREATE TABLE teams (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    manager_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(organization_id, name)
);

COMMENT ON TABLE teams IS 'Teams within organizations';

CREATE TABLE team_members (
    id SERIAL PRIMARY KEY,
    team_id INTEGER NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(team_id, user_id)
);

COMMENT ON TABLE team_members IS 'Team membership';

-- ============================================================================
-- CRM - CONTACTS & ACCOUNTS
-- ============================================================================

CREATE TABLE accounts (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    website VARCHAR(255),
    industry VARCHAR(100),
    employee_count INTEGER,
    annual_revenue DECIMAL(15, 2),
    description TEXT,
    owner_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    parent_account_id INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
    billing_street VARCHAR(255),
    billing_city VARCHAR(100),
    billing_state VARCHAR(100),
    billing_postal_code VARCHAR(20),
    billing_country VARCHAR(100),
    shipping_street VARCHAR(255),
    shipping_city VARCHAR(100),
    shipping_state VARCHAR(100),
    shipping_postal_code VARCHAR(20),
    shipping_country VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE accounts IS 'Customer and prospect companies';

CREATE TABLE contacts (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    account_id INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(20),
    mobile VARCHAR(20),
    title VARCHAR(100),
    department VARCHAR(100),
    owner_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    mailing_street VARCHAR(255),
    mailing_city VARCHAR(100),
    mailing_state VARCHAR(100),
    mailing_postal_code VARCHAR(20),
    mailing_country VARCHAR(100),
    description TEXT,
    linkedin_url VARCHAR(500),
    twitter_handle VARCHAR(100),
    is_primary BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE contacts IS 'Individual contact persons';

CREATE TABLE leads (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(20),
    company VARCHAR(255),
    title VARCHAR(100),
    status lead_status DEFAULT 'new',
    source VARCHAR(100),
    industry VARCHAR(100),
    owner_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    description TEXT,
    converted_at TIMESTAMP,
    converted_account_id INTEGER REFERENCES accounts(id),
    converted_contact_id INTEGER REFERENCES contacts(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE leads IS 'Sales leads before conversion';

-- ============================================================================
-- CRM - OPPORTUNITIES & PIPELINE
-- ============================================================================

CREATE TABLE pipelines (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    is_default BOOLEAN DEFAULT FALSE,
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(organization_id, name)
);

COMMENT ON TABLE pipelines IS 'Sales pipelines';

CREATE TABLE pipeline_stages (
    id SERIAL PRIMARY KEY,
    pipeline_id INTEGER NOT NULL REFERENCES pipelines(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    stage_type deal_stage NOT NULL,
    probability INTEGER DEFAULT 0 CHECK (probability >= 0 AND probability <= 100),
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE pipeline_stages IS 'Stages within sales pipelines';

CREATE TABLE deals (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    account_id INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
    contact_id INTEGER REFERENCES contacts(id) ON DELETE SET NULL,
    pipeline_id INTEGER NOT NULL REFERENCES pipelines(id) ON DELETE RESTRICT,
    stage_id INTEGER NOT NULL REFERENCES pipeline_stages(id) ON DELETE RESTRICT,
    owner_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    amount DECIMAL(15, 2),
    probability INTEGER DEFAULT 0 CHECK (probability >= 0 AND probability <= 100),
    expected_close_date DATE,
    actual_close_date DATE,
    description TEXT,
    next_step TEXT,
    lead_source VARCHAR(100),
    competitors TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE deals IS 'Sales opportunities';

-- ============================================================================
-- PRODUCTS & PRICING
-- ============================================================================

CREATE TABLE product_categories (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    parent_id INTEGER REFERENCES product_categories(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(organization_id, name)
);

COMMENT ON TABLE product_categories IS 'Product categorization';

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    sku VARCHAR(100),
    category_id INTEGER REFERENCES product_categories(id),
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    is_recurring BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(organization_id, sku)
);

COMMENT ON TABLE products IS 'Products and services catalog';

CREATE TABLE price_books (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(organization_id, name)
);

COMMENT ON TABLE price_books IS 'Price books for different markets/segments';

CREATE TABLE price_book_entries (
    id SERIAL PRIMARY KEY,
    price_book_id INTEGER NOT NULL REFERENCES price_books(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    unit_price DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(price_book_id, product_id)
);

COMMENT ON TABLE price_book_entries IS 'Product prices in price books';

CREATE TABLE deal_products (
    id SERIAL PRIMARY KEY,
    deal_id INTEGER NOT NULL REFERENCES deals(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id),
    quantity INTEGER DEFAULT 1,
    unit_price DECIMAL(10, 2) NOT NULL,
    discount_percent DECIMAL(5, 2) DEFAULT 0,
    total_price DECIMAL(15, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE deal_products IS 'Products associated with deals';

-- ============================================================================
-- SUBSCRIPTIONS & BILLING
-- ============================================================================

CREATE TABLE subscription_plans (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    billing_interval VARCHAR(20) NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    trial_days INTEGER DEFAULT 0,
    features JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE subscription_plans IS 'Recurring subscription plans';

CREATE TABLE subscriptions (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    plan_id INTEGER NOT NULL REFERENCES subscription_plans(id),
    status subscription_status DEFAULT 'trialing',
    current_period_start DATE NOT NULL,
    current_period_end DATE NOT NULL,
    trial_end DATE,
    cancel_at DATE,
    cancelled_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE subscriptions IS 'Customer subscriptions';

CREATE TABLE invoices (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    invoice_number VARCHAR(50) UNIQUE NOT NULL,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
    subscription_id INTEGER REFERENCES subscriptions(id),
    status invoice_status DEFAULT 'draft',
    subtotal DECIMAL(15, 2) NOT NULL,
    tax_amount DECIMAL(15, 2) DEFAULT 0,
    discount_amount DECIMAL(15, 2) DEFAULT 0,
    total_amount DECIMAL(15, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    issue_date DATE NOT NULL,
    due_date DATE NOT NULL,
    paid_date DATE,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE invoices IS 'Customer invoices';

CREATE TABLE invoice_line_items (
    id SERIAL PRIMARY KEY,
    invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    product_id INTEGER REFERENCES products(id),
    description TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL,
    total_price DECIMAL(15, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE invoice_line_items IS 'Invoice line items';

CREATE TABLE payments (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    invoice_id INTEGER REFERENCES invoices(id) ON DELETE SET NULL,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
    amount DECIMAL(15, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    payment_method VARCHAR(50),
    status payment_status DEFAULT 'pending',
    transaction_id VARCHAR(255),
    payment_gateway VARCHAR(100),
    payment_date DATE,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE payments IS 'Payment transactions';

-- ============================================================================
-- SUPPORT TICKETS
-- ============================================================================

CREATE TABLE ticket_categories (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    parent_id INTEGER REFERENCES ticket_categories(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(organization_id, name)
);

COMMENT ON TABLE ticket_categories IS 'Support ticket categories';

CREATE TABLE tickets (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    ticket_number VARCHAR(50) UNIQUE NOT NULL,
    account_id INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
    contact_id INTEGER REFERENCES contacts(id) ON DELETE SET NULL,
    category_id INTEGER REFERENCES ticket_categories(id),
    subject VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    status ticket_status DEFAULT 'open',
    priority ticket_priority DEFAULT 'medium',
    assigned_to INTEGER REFERENCES users(id) ON DELETE SET NULL,
    team_id INTEGER REFERENCES teams(id),
    source VARCHAR(50),
    created_by INTEGER REFERENCES users(id),
    resolved_at TIMESTAMP,
    closed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE tickets IS 'Customer support tickets';

CREATE TABLE ticket_comments (
    id SERIAL PRIMARY KEY,
    ticket_id INTEGER NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    comment TEXT NOT NULL,
    is_internal BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE ticket_comments IS 'Ticket conversation threads';

CREATE TABLE ticket_attachments (
    id SERIAL PRIMARY KEY,
    ticket_id INTEGER NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    comment_id INTEGER REFERENCES ticket_comments(id) ON DELETE CASCADE,
    file_name VARCHAR(255) NOT NULL,
    file_url VARCHAR(500) NOT NULL,
    file_size INTEGER,
    mime_type VARCHAR(100),
    uploaded_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE ticket_attachments IS 'Files attached to tickets';

-- ============================================================================
-- ACTIVITIES & TASKS
-- ============================================================================

CREATE TABLE activities (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    activity_type activity_type NOT NULL,
    subject VARCHAR(255) NOT NULL,
    description TEXT,
    related_to_type VARCHAR(50),
    related_to_id INTEGER,
    account_id INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
    contact_id INTEGER REFERENCES contacts(id) ON DELETE SET NULL,
    deal_id INTEGER REFERENCES deals(id) ON DELETE SET NULL,
    owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    scheduled_at TIMESTAMP,
    duration_minutes INTEGER,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE activities IS 'Sales and support activities (calls, meetings, etc)';

CREATE TABLE tasks (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    subject VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'not_started',
    priority task_priority DEFAULT 'medium',
    assigned_to INTEGER REFERENCES users(id) ON DELETE SET NULL,
    related_to_type VARCHAR(50),
    related_to_id INTEGER,
    due_date DATE,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE tasks IS 'Action items and to-dos';

-- ============================================================================
-- MARKETING CAMPAIGNS
-- ============================================================================

CREATE TABLE campaigns (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    campaign_type VARCHAR(50),
    status campaign_status DEFAULT 'draft',
    start_date DATE,
    end_date DATE,
    budget DECIMAL(15, 2),
    expected_revenue DECIMAL(15, 2),
    actual_cost DECIMAL(15, 2),
    owner_id INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE campaigns IS 'Marketing campaigns';

CREATE TABLE campaign_members (
    id SERIAL PRIMARY KEY,
    campaign_id INTEGER NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
    contact_id INTEGER REFERENCES contacts(id) ON DELETE CASCADE,
    lead_id INTEGER REFERENCES leads(id) ON DELETE CASCADE,
    status VARCHAR(50) DEFAULT 'sent',
    responded BOOLEAN DEFAULT FALSE,
    responded_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (
        (contact_id IS NOT NULL AND lead_id IS NULL) OR
        (contact_id IS NULL AND lead_id IS NOT NULL)
    )
);

COMMENT ON TABLE campaign_members IS 'Campaign recipients and responses';

-- ============================================================================
-- EMAILS & COMMUNICATIONS
-- ============================================================================

CREATE TABLE email_templates (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    subject VARCHAR(255) NOT NULL,
    body_html TEXT NOT NULL,
    body_text TEXT,
    category VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(organization_id, name)
);

COMMENT ON TABLE email_templates IS 'Email templates for campaigns and workflows';

CREATE TABLE emails (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    from_address VARCHAR(255) NOT NULL,
    to_address VARCHAR(255) NOT NULL,
    cc_address TEXT,
    bcc_address TEXT,
    subject VARCHAR(255) NOT NULL,
    body_html TEXT,
    body_text TEXT,
    status VARCHAR(50) DEFAULT 'draft',
    sent_at TIMESTAMP,
    opened_at TIMESTAMP,
    clicked_at TIMESTAMP,
    bounced_at TIMESTAMP,
    related_to_type VARCHAR(50),
    related_to_id INTEGER,
    campaign_id INTEGER REFERENCES campaigns(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE emails IS 'Email communication log';

-- ============================================================================
-- DOCUMENTS & FILES
-- ============================================================================

CREATE TABLE folders (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    parent_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
    is_public BOOLEAN DEFAULT FALSE,
    created_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE folders IS 'Document folder structure';

CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    file_url VARCHAR(500) NOT NULL,
    file_size INTEGER,
    mime_type VARCHAR(100),
    version INTEGER DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE,
    uploaded_by INTEGER REFERENCES users(id),
    related_to_type VARCHAR(50),
    related_to_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE documents IS 'Document management';

-- ============================================================================
-- REPORTS & DASHBOARDS
-- ============================================================================

CREATE TABLE dashboards (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    owner_id INTEGER REFERENCES users(id),
    is_public BOOLEAN DEFAULT FALSE,
    layout JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE dashboards IS 'Custom dashboards';

CREATE TABLE reports (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    report_type VARCHAR(50) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    filters JSONB DEFAULT '{}',
    columns JSONB DEFAULT '[]',
    owner_id INTEGER REFERENCES users(id),
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE reports IS 'Custom reports';

-- ============================================================================
-- AUDIT & LOGGING
-- ============================================================================

CREATE TABLE audit_logs (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER REFERENCES organizations(id) ON DELETE SET NULL,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id INTEGER,
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE audit_logs IS 'Audit trail for all changes';

CREATE TABLE system_logs (
    id SERIAL PRIMARY KEY,
    log_level VARCHAR(20) NOT NULL,
    message TEXT NOT NULL,
    context JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE system_logs IS 'System event logs';

-- ============================================================================
-- NOTIFICATIONS
-- ============================================================================

CREATE TABLE notification_preferences (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    email_enabled BOOLEAN DEFAULT TRUE,
    push_enabled BOOLEAN DEFAULT TRUE,
    sms_enabled BOOLEAN DEFAULT FALSE,
    preferences JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE notification_preferences IS 'User notification settings';

CREATE TABLE notifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    notification_type VARCHAR(50) NOT NULL,
    related_to_type VARCHAR(50),
    related_to_id INTEGER,
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE notifications IS 'In-app notifications';

-- ============================================================================
-- INTEGRATIONS
-- ============================================================================

CREATE TABLE integrations (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    integration_type VARCHAR(50) NOT NULL,
    config JSONB DEFAULT '{}',
    credentials JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT TRUE,
    last_sync_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(organization_id, name)
);

COMMENT ON TABLE integrations IS 'Third-party integrations';

CREATE TABLE webhooks (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    url VARCHAR(500) NOT NULL,
    event_types TEXT[] NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    secret VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE webhooks IS 'Webhook subscriptions';

CREATE TABLE webhook_deliveries (
    id SERIAL PRIMARY KEY,
    webhook_id INTEGER NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL,
    payload JSONB NOT NULL,
    response_status INTEGER,
    response_body TEXT,
    delivered_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE webhook_deliveries IS 'Webhook delivery log';

-- ============================================================================
-- CUSTOM FIELDS (EAV Pattern)
-- ============================================================================

CREATE TABLE custom_field_definitions (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    entity_type VARCHAR(50) NOT NULL,
    field_name VARCHAR(100) NOT NULL,
    field_type VARCHAR(20) NOT NULL,
    is_required BOOLEAN DEFAULT FALSE,
    default_value TEXT,
    options JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(organization_id, entity_type, field_name)
);

COMMENT ON TABLE custom_field_definitions IS 'Custom field definitions';

CREATE TABLE custom_field_values (
    id SERIAL PRIMARY KEY,
    field_definition_id INTEGER NOT NULL REFERENCES custom_field_definitions(id) ON DELETE CASCADE,
    entity_id INTEGER NOT NULL,
    value TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(field_definition_id, entity_id)
);

COMMENT ON TABLE custom_field_values IS 'Custom field values';

-- ============================================================================
-- COMPREHENSIVE INDEXES
-- ============================================================================

-- Organizations
CREATE INDEX idx_orgs_slug ON organizations(slug);
CREATE INDEX idx_orgs_status ON organizations(account_status);
CREATE INDEX idx_orgs_created_at ON organizations(created_at DESC);

-- Users
CREATE INDEX idx_users_org_id ON users(organization_id);
CREATE INDEX idx_users_email ON users(organization_id, email);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_is_active ON users(is_active);

-- Teams
CREATE INDEX idx_teams_org_id ON teams(organization_id);
CREATE INDEX idx_team_members_team_id ON team_members(team_id);
CREATE INDEX idx_team_members_user_id ON team_members(user_id);

-- Accounts
CREATE INDEX idx_accounts_org_id ON accounts(organization_id);
CREATE INDEX idx_accounts_owner_id ON accounts(owner_id);
CREATE INDEX idx_accounts_name_trgm ON accounts USING gin (name gin_trgm_ops);
CREATE INDEX idx_accounts_created_at ON accounts(created_at DESC);

-- Contacts
CREATE INDEX idx_contacts_org_id ON contacts(organization_id);
CREATE INDEX idx_contacts_account_id ON contacts(account_id);
CREATE INDEX idx_contacts_owner_id ON contacts(owner_id);
CREATE INDEX idx_contacts_email ON contacts(email);
CREATE INDEX idx_contacts_name ON contacts(organization_id, last_name, first_name);

-- Leads
CREATE INDEX idx_leads_org_id ON leads(organization_id);
CREATE INDEX idx_leads_status ON leads(status);
CREATE INDEX idx_leads_owner_id ON leads(owner_id);
CREATE INDEX idx_leads_created_at ON leads(created_at DESC);
CREATE INDEX idx_leads_converted ON leads(converted_at) WHERE converted_at IS NOT NULL;

-- Pipelines & Stages
CREATE INDEX idx_pipelines_org_id ON pipelines(organization_id);
CREATE INDEX idx_pipeline_stages_pipeline_id ON pipeline_stages(pipeline_id);

-- Deals
CREATE INDEX idx_deals_org_id ON deals(organization_id);
CREATE INDEX idx_deals_account_id ON deals(account_id);
CREATE INDEX idx_deals_contact_id ON deals(contact_id);
CREATE INDEX idx_deals_pipeline_id ON deals(pipeline_id);
CREATE INDEX idx_deals_stage_id ON deals(stage_id);
CREATE INDEX idx_deals_owner_id ON deals(owner_id);
CREATE INDEX idx_deals_close_date ON deals(expected_close_date);
CREATE INDEX idx_deals_created_at ON deals(created_at DESC);

-- Products
CREATE INDEX idx_products_org_id ON products(organization_id);
CREATE INDEX idx_products_category_id ON products(category_id);
CREATE INDEX idx_products_is_active ON products(is_active);

-- Price Books
CREATE INDEX idx_price_books_org_id ON price_books(organization_id);
CREATE INDEX idx_price_book_entries_book_id ON price_book_entries(price_book_id);
CREATE INDEX idx_price_book_entries_product_id ON price_book_entries(product_id);

-- Subscriptions
CREATE INDEX idx_subscriptions_org_id ON subscriptions(organization_id);
CREATE INDEX idx_subscriptions_account_id ON subscriptions(account_id);
CREATE INDEX idx_subscriptions_plan_id ON subscriptions(plan_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);

-- Invoices
CREATE INDEX idx_invoices_org_id ON invoices(organization_id);
CREATE INDEX idx_invoices_account_id ON invoices(account_id);
CREATE INDEX idx_invoices_status ON invoices(status);
CREATE INDEX idx_invoices_due_date ON invoices(due_date);
CREATE INDEX idx_invoices_created_at ON invoices(created_at DESC);

-- Payments
CREATE INDEX idx_payments_org_id ON payments(organization_id);
CREATE INDEX idx_payments_invoice_id ON payments(invoice_id);
CREATE INDEX idx_payments_account_id ON payments(account_id);
CREATE INDEX idx_payments_status ON payments(status);

-- Tickets
CREATE INDEX idx_tickets_org_id ON tickets(organization_id);
CREATE INDEX idx_tickets_account_id ON tickets(account_id);
CREATE INDEX idx_tickets_contact_id ON tickets(contact_id);
CREATE INDEX idx_tickets_status ON tickets(status);
CREATE INDEX idx_tickets_priority ON tickets(priority);
CREATE INDEX idx_tickets_assigned_to ON tickets(assigned_to);
CREATE INDEX idx_tickets_team_id ON tickets(team_id);
CREATE INDEX idx_tickets_created_at ON tickets(created_at DESC);

-- Ticket Comments
CREATE INDEX idx_ticket_comments_ticket_id ON ticket_comments(ticket_id);
CREATE INDEX idx_ticket_comments_user_id ON ticket_comments(user_id);

-- Activities
CREATE INDEX idx_activities_org_id ON activities(organization_id);
CREATE INDEX idx_activities_type ON activities(activity_type);
CREATE INDEX idx_activities_owner_id ON activities(owner_id);
CREATE INDEX idx_activities_account_id ON activities(account_id);
CREATE INDEX idx_activities_contact_id ON activities(contact_id);
CREATE INDEX idx_activities_deal_id ON activities(deal_id);
CREATE INDEX idx_activities_scheduled_at ON activities(scheduled_at);

-- Tasks
CREATE INDEX idx_tasks_org_id ON tasks(organization_id);
CREATE INDEX idx_tasks_assigned_to ON tasks(assigned_to);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_due_date ON tasks(due_date);

-- Campaigns
CREATE INDEX idx_campaigns_org_id ON campaigns(organization_id);
CREATE INDEX idx_campaigns_status ON campaigns(status);
CREATE INDEX idx_campaign_members_campaign_id ON campaign_members(campaign_id);
CREATE INDEX idx_campaign_members_contact_id ON campaign_members(contact_id);
CREATE INDEX idx_campaign_members_lead_id ON campaign_members(lead_id);

-- Emails
CREATE INDEX idx_emails_org_id ON emails(organization_id);
CREATE INDEX idx_emails_status ON emails(status);
CREATE INDEX idx_emails_sent_at ON emails(sent_at DESC);

-- Documents
CREATE INDEX idx_documents_org_id ON documents(organization_id);
CREATE INDEX idx_documents_folder_id ON documents(folder_id);
CREATE INDEX idx_folders_org_id ON folders(organization_id);
CREATE INDEX idx_folders_parent_id ON folders(parent_id);

-- Audit Logs
CREATE INDEX idx_audit_logs_org_id ON audit_logs(organization_id);
CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);

-- Notifications
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_is_read ON notifications(user_id, is_read);
CREATE INDEX idx_notifications_created_at ON notifications(created_at DESC);

-- Integrations
CREATE INDEX idx_integrations_org_id ON integrations(organization_id);
CREATE INDEX idx_webhooks_org_id ON webhooks(organization_id);
CREATE INDEX idx_webhook_deliveries_webhook_id ON webhook_deliveries(webhook_id);

-- ============================================================================
-- VIEWS
-- ============================================================================

-- Sales Pipeline Overview
CREATE VIEW sales_pipeline_summary AS
SELECT
    p.organization_id,
    p.id AS pipeline_id,
    p.name AS pipeline_name,
    ps.id AS stage_id,
    ps.name AS stage_name,
    ps.stage_type,
    COUNT(d.id) AS deal_count,
    SUM(d.amount) AS total_value,
    AVG(d.probability)::NUMERIC(5,2) AS avg_probability,
    SUM(d.amount * d.probability / 100.0)::NUMERIC(15,2) AS weighted_value
FROM pipelines p
JOIN pipeline_stages ps ON p.id = ps.pipeline_id
LEFT JOIN deals d ON ps.id = d.stage_id
GROUP BY p.organization_id, p.id, p.name, ps.id, ps.name, ps.stage_type
ORDER BY p.id, ps.display_order;

COMMENT ON VIEW sales_pipeline_summary IS 'Sales pipeline metrics by stage';

-- Account Revenue Summary
CREATE VIEW account_revenue AS
SELECT
    a.id AS account_id,
    a.organization_id,
    a.name AS account_name,
    COUNT(DISTINCT i.id) AS invoice_count,
    SUM(CASE WHEN i.status = 'paid' THEN i.total_amount ELSE 0 END) AS total_paid,
    SUM(CASE WHEN i.status = 'overdue' THEN i.total_amount ELSE 0 END) AS total_overdue,
    MAX(i.paid_date) AS last_payment_date
FROM accounts a
LEFT JOIN invoices i ON a.id = i.account_id
GROUP BY a.id, a.organization_id, a.name;

COMMENT ON VIEW account_revenue IS 'Revenue metrics by account';

-- Active Subscriptions View
CREATE VIEW active_subscriptions AS
SELECT
    s.id,
    s.organization_id,
    a.name AS account_name,
    sp.name AS plan_name,
    sp.price AS monthly_price,
    s.status,
    s.current_period_start,
    s.current_period_end,
    (s.current_period_end - CURRENT_DATE) AS days_until_renewal
FROM subscriptions s
JOIN accounts a ON s.account_id = a.id
JOIN subscription_plans sp ON s.plan_id = sp.id
WHERE s.status IN ('active', 'trialing');

COMMENT ON VIEW active_subscriptions IS 'Currently active subscriptions';

-- Support Ticket Metrics
CREATE VIEW ticket_metrics AS
SELECT
    t.organization_id,
    t.status,
    t.priority,
    COUNT(*) AS ticket_count,
    AVG(EXTRACT(EPOCH FROM (COALESCE(t.resolved_at, CURRENT_TIMESTAMP) - t.created_at)) / 3600)::NUMERIC(10,2) AS avg_resolution_hours,
    COUNT(CASE WHEN t.resolved_at IS NOT NULL THEN 1 END) AS resolved_count,
    COUNT(CASE WHEN t.resolved_at IS NULL THEN 1 END) AS open_count
FROM tickets t
GROUP BY t.organization_id, t.status, t.priority;

COMMENT ON VIEW ticket_metrics IS 'Support ticket statistics';

-- User Activity Summary
CREATE VIEW user_activity_summary AS
SELECT
    u.id AS user_id,
    u.organization_id,
    u.first_name || ' ' || u.last_name AS user_name,
    u.role,
    COUNT(DISTINCT a.id) AS activity_count,
    COUNT(DISTINCT t.id) AS task_count,
    COUNT(DISTINCT CASE WHEN d.owner_id = u.id THEN d.id END) AS deals_owned,
    SUM(CASE WHEN d.owner_id = u.id THEN d.amount ELSE 0 END) AS total_deal_value
FROM users u
LEFT JOIN activities a ON u.id = a.owner_id
LEFT JOIN tasks t ON u.id = t.assigned_to
LEFT JOIN deals d ON u.id = d.owner_id
GROUP BY u.id, u.organization_id, u.first_name, u.last_name, u.role;

COMMENT ON VIEW user_activity_summary IS 'User performance metrics';

-- Lead Conversion Funnel
CREATE VIEW lead_conversion_funnel AS
SELECT
    l.organization_id,
    l.source,
    COUNT(*) AS total_leads,
    COUNT(CASE WHEN l.status = 'qualified' THEN 1 END) AS qualified_leads,
    COUNT(CASE WHEN l.converted_at IS NOT NULL THEN 1 END) AS converted_leads,
    (COUNT(CASE WHEN l.converted_at IS NOT NULL THEN 1 END)::FLOAT / NULLIF(COUNT(*), 0) * 100)::NUMERIC(5,2) AS conversion_rate
FROM leads l
GROUP BY l.organization_id, l.source;

COMMENT ON VIEW lead_conversion_funnel IS 'Lead conversion metrics by source';

-- Monthly Revenue Trends
CREATE VIEW monthly_revenue AS
SELECT
    i.organization_id,
    DATE_TRUNC('month', i.paid_date)::DATE AS month,
    COUNT(*) AS invoice_count,
    SUM(i.total_amount) AS total_revenue,
    AVG(i.total_amount)::NUMERIC(10,2) AS avg_invoice_value
FROM invoices i
WHERE i.status = 'paid' AND i.paid_date IS NOT NULL
GROUP BY i.organization_id, DATE_TRUNC('month', i.paid_date)
ORDER BY month DESC;

COMMENT ON VIEW monthly_revenue IS 'Monthly revenue trends';

-- Overdue Invoices
CREATE VIEW overdue_invoices AS
SELECT
    i.id,
    i.organization_id,
    i.invoice_number,
    a.name AS account_name,
    i.total_amount,
    i.due_date,
    CURRENT_DATE - i.due_date AS days_overdue,
    i.created_at
FROM invoices i
JOIN accounts a ON i.account_id = a.id
WHERE i.status = 'overdue'
ORDER BY i.due_date;

COMMENT ON VIEW overdue_invoices IS 'Invoices past due date';

-- Top Performing Products
CREATE VIEW top_products AS
SELECT
    p.id,
    p.organization_id,
    p.name AS product_name,
    COUNT(DISTINCT dp.deal_id) AS times_sold,
    SUM(dp.quantity) AS total_quantity_sold,
    SUM(dp.total_price) AS total_revenue
FROM products p
LEFT JOIN deal_products dp ON p.id = dp.product_id
GROUP BY p.id, p.organization_id, p.name
ORDER BY total_revenue DESC;

COMMENT ON VIEW top_products IS 'Product sales performance from deals';

-- Campaign Performance
CREATE VIEW campaign_performance AS
SELECT
    c.id,
    c.organization_id,
    c.name AS campaign_name,
    c.campaign_type,
    c.status,
    COUNT(DISTINCT cm.id) AS total_recipients,
    COUNT(CASE WHEN cm.responded = TRUE THEN 1 END) AS responded_count,
    (COUNT(CASE WHEN cm.responded = TRUE THEN 1 END)::FLOAT / NULLIF(COUNT(DISTINCT cm.id), 0) * 100)::NUMERIC(5,2) AS response_rate,
    c.budget,
    c.actual_cost,
    c.expected_revenue
FROM campaigns c
LEFT JOIN campaign_members cm ON c.id = cm.campaign_id
GROUP BY c.id, c.organization_id, c.name, c.campaign_type, c.status, c.budget, c.actual_cost, c.expected_revenue;

COMMENT ON VIEW campaign_performance IS 'Marketing campaign metrics';

-- ============================================================================
-- SAMPLE DATA
-- ============================================================================

-- Insert organizations
INSERT INTO organizations (name, slug, domain, account_status, trial_ends_at) VALUES
('Acme Corporation', 'acme-corp', 'acme.com', 'active', NULL),
('TechStart Inc', 'techstart', 'techstart.io', 'active', NULL),
('Global Solutions', 'global-solutions', 'globalsolutions.com', 'trial', CURRENT_TIMESTAMP + INTERVAL '14 days'),
('Enterprise Systems', 'enterprise-sys', 'enterprisesys.com', 'active', NULL);

-- Insert users
INSERT INTO users (organization_id, email, password_hash, first_name, last_name, role, is_active, email_verified) VALUES
(1, 'john@acme.com', '$2b$10$hash1', 'John', 'Doe', 'owner', TRUE, TRUE),
(1, 'sarah@acme.com', '$2b$10$hash2', 'Sarah', 'Johnson', 'admin', TRUE, TRUE),
(1, 'mike@acme.com', '$2b$10$hash3', 'Mike', 'Chen', 'sales_rep', TRUE, TRUE),
(1, 'lisa@acme.com', '$2b$10$hash4', 'Lisa', 'Wang', 'sales_rep', TRUE, TRUE),
(1, 'david@acme.com', '$2b$10$hash5', 'David', 'Miller', 'support_agent', TRUE, TRUE),
(2, 'alice@techstart.io', '$2b$10$hash6', 'Alice', 'Smith', 'owner', TRUE, TRUE),
(2, 'bob@techstart.io', '$2b$10$hash7', 'Bob', 'Brown', 'sales_rep', TRUE, TRUE),
(3, 'emma@globalsolutions.com', '$2b$10$hash8', 'Emma', 'Davis', 'owner', TRUE, TRUE),
(4, 'james@enterprisesys.com', '$2b$10$hash9', 'James', 'Wilson', 'owner', TRUE, TRUE);

-- Insert teams
INSERT INTO teams (organization_id, name, description, manager_id) VALUES
(1, 'Sales Team', 'Main sales team', 2),
(1, 'Support Team', 'Customer support', 2),
(2, 'Revenue Team', 'Sales and revenue operations', 6);

-- Insert team members
INSERT INTO team_members (team_id, user_id) VALUES
(1, 3), (1, 4),
(2, 5),
(3, 7);

-- Insert accounts (customers/prospects)
INSERT INTO accounts (organization_id, name, website, industry, employee_count, annual_revenue, owner_id, billing_city, billing_state, billing_country) VALUES
(1, 'ABC Manufacturing', 'www.abcmfg.com', 'Manufacturing', 250, 5000000.00, 3, 'Detroit', 'MI', 'USA'),
(1, 'XYZ Retail', 'www.xyzretail.com', 'Retail', 150, 3000000.00, 3, 'New York', 'NY', 'USA'),
(1, 'CloudFirst Technologies', 'www.cloudfirst.io', 'Technology', 50, 2000000.00, 4, 'San Francisco', 'CA', 'USA'),
(1, 'GreenEnergy Corp', 'www.greenenergy.com', 'Energy', 400, 15000000.00, 4, 'Houston', 'TX', 'USA'),
(2, 'StartupX', 'www.startupx.com', 'Technology', 10, 500000.00, 7, 'Austin', 'TX', 'USA'),
(2, 'FinTech Solutions', 'www.fintechsol.com', 'Financial Services', 75, 4000000.00, 7, 'Boston', 'MA', 'USA');

-- Insert contacts
INSERT INTO contacts (organization_id, account_id, first_name, last_name, email, phone, title, department, owner_id, is_primary) VALUES
(1, 1, 'Robert', 'Johnson', 'rjohnson@abcmfg.com', '+1-313-555-0001', 'CEO', 'Executive', 3, TRUE),
(1, 1, 'Mary', 'Williams', 'mwilliams@abcmfg.com', '+1-313-555-0002', 'CFO', 'Finance', 3, FALSE),
(1, 2, 'Patricia', 'Brown', 'pbrown@xyzretail.com', '+1-212-555-0001', 'VP Operations', 'Operations', 3, TRUE),
(1, 3, 'Michael', 'Davis', 'mdavis@cloudfirst.io', '+1-415-555-0001', 'CTO', 'Engineering', 4, TRUE),
(1, 4, 'Jennifer', 'Garcia', 'jgarcia@greenenergy.com', '+1-713-555-0001', 'Director of IT', 'IT', 4, TRUE),
(2, 5, 'William', 'Martinez', 'wmartinez@startupx.com', '+1-512-555-0001', 'Founder', 'Executive', 7, TRUE),
(2, 6, 'Linda', 'Rodriguez', 'lrodriguez@fintechsol.com', '+1-617-555-0001', 'VP Sales', 'Sales', 7, TRUE);

-- Insert leads
INSERT INTO leads (organization_id, first_name, last_name, email, phone, company, title, status, source, owner_id, rating) VALUES
(1, 'Daniel', 'Anderson', 'danderson@newcompany.com', '+1-555-0101', 'NewCompany LLC', 'Manager', 'new', 'Website', 3, 3),
(1, 'Jessica', 'Thomas', 'jthomas@futuretech.com', '+1-555-0102', 'FutureTech', 'Director', 'contacted', 'Referral', 3, 4),
(1, 'Christopher', 'Jackson', 'cjackson@innovate.io', '+1-555-0103', 'Innovate Systems', 'VP', 'qualified', 'Trade Show', 4, 5),
(2, 'Sarah', 'White', 'swhite@rapidgrowth.com', '+1-555-0104', 'RapidGrowth Inc', 'CEO', 'new', 'LinkedIn', 7, 3);

-- Insert pipelines
INSERT INTO pipelines (organization_id, name, description, is_default) VALUES
(1, 'Standard Sales Pipeline', 'Default sales process', TRUE),
(2, 'Enterprise Sales', 'Enterprise deal process', TRUE);

-- Insert pipeline stages
INSERT INTO pipeline_stages (pipeline_id, name, stage_type, probability, display_order) VALUES
(1, 'Prospecting', 'prospecting', 10, 1),
(1, 'Qualification', 'qualification', 25, 2),
(1, 'Proposal', 'proposal', 50, 3),
(1, 'Negotiation', 'negotiation', 75, 4),
(1, 'Closed Won', 'closed_won', 100, 5),
(1, 'Closed Lost', 'closed_lost', 0, 6),
(2, 'Discovery', 'prospecting', 10, 1),
(2, 'Proof of Concept', 'qualification', 30, 2),
(2, 'Proposal', 'proposal', 60, 3),
(2, 'Contract Review', 'negotiation', 85, 4),
(2, 'Won', 'closed_won', 100, 5),
(2, 'Lost', 'closed_lost', 0, 6);

-- Insert product categories
INSERT INTO product_categories (organization_id, name, description) VALUES
(1, 'Software Licenses', 'Software licensing products'),
(1, 'Professional Services', 'Consulting and implementation'),
(1, 'Support Plans', 'Technical support subscriptions'),
(2, 'SaaS Products', 'Cloud software subscriptions');

-- Insert products
INSERT INTO products (organization_id, name, sku, category_id, description, is_active, is_recurring) VALUES
(1, 'Enterprise CRM License', 'CRM-ENT-001', 1, 'Enterprise CRM platform annual license', TRUE, TRUE),
(1, 'Professional CRM License', 'CRM-PRO-001', 1, 'Professional CRM platform annual license', TRUE, TRUE),
(1, 'Implementation Services', 'SVC-IMPL-001', 2, 'CRM implementation and setup', TRUE, FALSE),
(1, 'Training Package', 'SVC-TRAIN-001', 2, 'User training program', TRUE, FALSE),
(1, 'Premium Support', 'SUP-PREM-001', 3, '24/7 premium support plan', TRUE, TRUE),
(2, 'Starter Plan', 'SAAS-START-001', 4, 'Starter subscription plan', TRUE, TRUE),
(2, 'Growth Plan', 'SAAS-GROW-001', 4, 'Growth subscription plan', TRUE, TRUE),
(2, 'Enterprise Plan', 'SAAS-ENT-001', 4, 'Enterprise subscription plan', TRUE, TRUE);

-- Insert price books
INSERT INTO price_books (organization_id, name, description, is_active, is_default) VALUES
(1, 'Standard Price Book', 'Default pricing', TRUE, TRUE),
(2, 'Standard Pricing', 'Default pricing', TRUE, TRUE);

-- Insert price book entries
INSERT INTO price_book_entries (price_book_id, product_id, unit_price) VALUES
(1, 1, 999.00), (1, 2, 499.00), (1, 3, 5000.00), (1, 4, 2000.00), (1, 5, 299.00),
(2, 6, 49.00), (2, 7, 199.00), (2, 8, 999.00);

-- Insert deals
INSERT INTO deals (organization_id, name, account_id, contact_id, pipeline_id, stage_id, owner_id, amount, probability, expected_close_date) VALUES
(1, 'ABC Manufacturing - Enterprise CRM', 1, 1, 1, 3, 3, 15000.00, 50, CURRENT_DATE + INTERVAL '30 days'),
(1, 'XYZ Retail - Professional CRM', 2, 3, 1, 2, 3, 7500.00, 25, CURRENT_DATE + INTERVAL '45 days'),
(1, 'CloudFirst - Implementation', 3, 4, 1, 4, 4, 25000.00, 75, CURRENT_DATE + INTERVAL '15 days'),
(1, 'GreenEnergy - Enterprise Deal', 4, 5, 1, 1, 4, 50000.00, 10, CURRENT_DATE + INTERVAL '90 days'),
(2, 'StartupX - Growth Plan', 5, 6, 2, 3, 7, 2400.00, 60, CURRENT_DATE + INTERVAL '20 days');

-- Insert subscription plans
INSERT INTO subscription_plans (organization_id, name, billing_interval, price, trial_days, is_active) VALUES
(1, 'Monthly Professional', 'month', 499.00, 14, TRUE),
(1, 'Annual Professional', 'year', 4990.00, 14, TRUE),
(1, 'Monthly Enterprise', 'month', 999.00, 30, TRUE),
(2, 'Starter Monthly', 'month', 49.00, 7, TRUE),
(2, 'Growth Monthly', 'month', 199.00, 14, TRUE);

-- Insert subscriptions
INSERT INTO subscriptions (organization_id, account_id, plan_id, status, current_period_start, current_period_end) VALUES
(1, 1, 2, 'active', CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE + INTERVAL '335 days'),
(1, 3, 3, 'active', CURRENT_DATE - INTERVAL '15 days', CURRENT_DATE + INTERVAL '15 days'),
(2, 5, 4, 'trialing', CURRENT_DATE - INTERVAL '3 days', CURRENT_DATE + INTERVAL '27 days');

-- Insert invoices
INSERT INTO invoices (organization_id, invoice_number, account_id, subscription_id, status, subtotal, tax_amount, total_amount, issue_date, due_date, paid_date) VALUES
(1, 'INV-2024-0001', 1, 1, 'paid', 4990.00, 399.20, 5389.20, CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE - INTERVAL '15 days', CURRENT_DATE - INTERVAL '20 days'),
(1, 'INV-2024-0002', 3, 2, 'paid', 999.00, 79.92, 1078.92, CURRENT_DATE - INTERVAL '15 days', CURRENT_DATE, CURRENT_DATE - INTERVAL '5 days'),
(1, 'INV-2024-0003', 2, NULL, 'sent', 7500.00, 600.00, 8100.00, CURRENT_DATE - INTERVAL '10 days', CURRENT_DATE + INTERVAL '20 days', NULL),
(2, 'INV-2024-T001', 5, 3, 'draft', 0.00, 0.00, 0.00, CURRENT_DATE, CURRENT_DATE + INTERVAL '30 days', NULL);

-- Insert invoice line items
INSERT INTO invoice_line_items (invoice_id, product_id, description, quantity, unit_price, total_price) VALUES
(1, 2, 'Professional CRM Annual License', 1, 4990.00, 4990.00),
(2, 1, 'Enterprise CRM Monthly License', 1, 999.00, 999.00),
(3, 3, 'CRM Implementation Services', 1, 5000.00, 5000.00),
(3, 4, 'Training Package - 10 users', 1, 2000.00, 2000.00),
(3, 5, 'Premium Support - 6 months', 1, 500.00, 500.00);

-- Insert payments
INSERT INTO payments (organization_id, invoice_id, account_id, amount, payment_method, status, transaction_id, payment_date) VALUES
(1, 1, 1, 5389.20, 'credit_card', 'completed', 'txn_abc123', CURRENT_DATE - INTERVAL '20 days'),
(1, 2, 3, 1078.92, 'bank_transfer', 'completed', 'txn_def456', CURRENT_DATE - INTERVAL '5 days');

-- Insert ticket categories
INSERT INTO ticket_categories (organization_id, name, description) VALUES
(1, 'Technical Support', 'Technical issues and bugs'),
(1, 'Billing', 'Billing and payment questions'),
(1, 'Feature Request', 'New feature suggestions'),
(2, 'General Support', 'General customer support');

-- Insert tickets
INSERT INTO tickets (organization_id, ticket_number, account_id, contact_id, category_id, subject, description, status, priority, assigned_to) VALUES
(1, 'TKT-001', 1, 1, 1, 'Cannot login to dashboard', 'User reports unable to access dashboard after password reset', 'in_progress', 'high', 5),
(1, 'TKT-002', 2, 3, 2, 'Invoice payment question', 'Customer asking about payment terms', 'resolved', 'low', 5),
(1, 'TKT-003', 3, 4, 3, 'Request API integration', 'Customer wants to integrate with external system', 'open', 'medium', 5),
(2, 'TKT-T001', 5, 6, 4, 'Help with onboarding', 'New customer needs setup assistance', 'pending', 'medium', NULL);

-- Insert ticket comments
INSERT INTO ticket_comments (ticket_id, user_id, comment, is_internal) VALUES
(1, 5, 'Looking into the issue. Can you confirm your email address?', FALSE),
(1, 3, 'My email is rjohnson@abcmfg.com', FALSE),
(1, 5, 'Found the issue - password reset email went to spam. Resending now.', FALSE),
(2, 5, 'Payment terms are Net 30 as per your contract.', FALSE),
(3, 5, 'Our API documentation is available at api.acme.com/docs', FALSE);

-- Insert activities
INSERT INTO activities (organization_id, activity_type, subject, description, account_id, contact_id, deal_id, owner_id, scheduled_at, duration_minutes) VALUES
(1, 'call', 'Discovery Call - ABC Manufacturing', 'Initial discovery call to understand requirements', 1, 1, 1, 3, CURRENT_TIMESTAMP - INTERVAL '2 days', 60),
(1, 'meeting', 'Demo Session - XYZ Retail', 'Product demonstration', 2, 3, 2, 3, CURRENT_TIMESTAMP + INTERVAL '3 days', 90),
(1, 'email', 'Proposal Follow-up', 'Following up on sent proposal', 3, 4, 3, 4, CURRENT_TIMESTAMP - INTERVAL '1 day', NULL),
(1, 'call', 'Contract Negotiation', 'Discussing contract terms', 4, 5, 4, 4, CURRENT_TIMESTAMP + INTERVAL '5 days', 45);

-- Insert tasks
INSERT INTO tasks (organization_id, subject, description, status, priority, assigned_to, due_date) VALUES
(1, 'Prepare proposal for ABC Manufacturing', 'Create detailed proposal including pricing', 'in_progress', 'high', 3, CURRENT_DATE + INTERVAL '2 days'),
(1, 'Follow up with XYZ Retail', 'Send follow-up email after demo', 'not_started', 'medium', 3, CURRENT_DATE + INTERVAL '1 day'),
(1, 'Schedule implementation kickoff', 'Set up kickoff meeting with CloudFirst', 'not_started', 'high', 4, CURRENT_DATE + INTERVAL '3 days');

-- Insert campaigns
INSERT INTO campaigns (organization_id, name, description, campaign_type, status, start_date, end_date, budget, owner_id) VALUES
(1, 'Summer 2024 Promotion', 'Q3 product promotion campaign', 'email', 'completed', CURRENT_DATE - INTERVAL '60 days', CURRENT_DATE - INTERVAL '30 days', 5000.00, 2),
(1, 'Webinar Series - Fall 2024', 'Educational webinar series', 'webinar', 'active', CURRENT_DATE - INTERVAL '15 days', CURRENT_DATE + INTERVAL '45 days', 3000.00, 2);

-- Insert campaign members
INSERT INTO campaign_members (campaign_id, contact_id, status, responded, responded_at) VALUES
(1, 1, 'sent', TRUE, CURRENT_TIMESTAMP - INTERVAL '50 days'),
(1, 2, 'sent', FALSE, NULL),
(1, 3, 'sent', TRUE, CURRENT_TIMESTAMP - INTERVAL '45 days'),
(2, 4, 'sent', TRUE, CURRENT_TIMESTAMP - INTERVAL '10 days'),
(2, 5, 'sent', FALSE, NULL);

-- Insert email templates
INSERT INTO email_templates (organization_id, name, subject, body_html, category, is_active) VALUES
(1, 'Welcome Email', 'Welcome to Acme CRM', '<h1>Welcome!</h1><p>Thank you for choosing Acme CRM...</p>', 'onboarding', TRUE),
(1, 'Invoice Reminder', 'Invoice Payment Reminder', '<p>This is a friendly reminder about invoice #{invoice_number}...</p>', 'billing', TRUE);

-- Insert notifications
INSERT INTO notifications (user_id, title, message, notification_type, is_read) VALUES
(3, 'New lead assigned', 'A new lead "Daniel Anderson" has been assigned to you', 'lead', FALSE),
(3, 'Deal moved to Proposal stage', 'Deal "ABC Manufacturing - Enterprise CRM" moved to Proposal stage', 'deal', TRUE),
(5, 'New ticket assigned', 'Ticket TKT-003 has been assigned to you', 'ticket', FALSE);

-- Insert audit logs (sample)
INSERT INTO audit_logs (organization_id, user_id, action, entity_type, entity_id, new_values, ip_address) VALUES
(1, 3, 'create', 'deal', 1, '{"name": "ABC Manufacturing - Enterprise CRM", "amount": 15000.00}'::jsonb, '192.168.1.100'),
(1, 3, 'update', 'deal', 1, '{"stage_id": 3}'::jsonb, '192.168.1.100'),
(1, 5, 'update', 'ticket', 1, '{"status": "in_progress"}'::jsonb, '192.168.1.101');

-- ============================================================================
-- TRIGGER FUNCTION FOR UPDATED_AT
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to all tables with updated_at column
DO $$
DECLARE
    t text;
BEGIN
    FOR t IN
        SELECT table_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND column_name = 'updated_at'
          AND table_name NOT LIKE 'pg_%'
    LOOP
        EXECUTE format('
            CREATE TRIGGER update_%I_updated_at
            BEFORE UPDATE ON %I
            FOR EACH ROW
            EXECUTE FUNCTION update_updated_at_column();
        ', t, t);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- DATABASE STATISTICS
-- ============================================================================

VACUUM ANALYZE;

SELECT
    'Database' AS object_type,
    current_database() AS name,
    'Enterprise SaaS CRM with 55+ tables, 10 views, 6 types' AS description
UNION ALL
SELECT
    'Tables' AS object_type,
    COUNT(*)::text AS name,
    'User-defined tables' AS description
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
UNION ALL
SELECT
    'Views' AS object_type,
    COUNT(*)::text AS name,
    'User-defined views' AS description
FROM information_schema.views
WHERE table_schema = 'public'
UNION ALL
SELECT
    'Indexes' AS object_type,
    COUNT(*)::text AS name,
    'User-defined indexes' AS description
FROM pg_indexes
WHERE schemaname = 'public';

-- ============================================================================
-- DATABASE: hr_system
-- ============================================================================

DROP DATABASE IF EXISTS hr_system;
CREATE DATABASE hr_system;
\c hr_system

CREATE TYPE emp_status AS ENUM ('active', 'probation', 'leave', 'resigned');
CREATE TYPE leave_type AS ENUM ('annual', 'sick', 'personal', 'maternity', 'other');
CREATE TYPE leave_status AS ENUM ('pending', 'approved', 'rejected', 'cancelled');

CREATE TABLE departments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    code VARCHAR(30) UNIQUE NOT NULL,
    parent_id INT REFERENCES departments(id),
    manager_name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    emp_no VARCHAR(30) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(120) UNIQUE NOT NULL,
    phone VARCHAR(30),
    department_id INT REFERENCES departments(id),
    title VARCHAR(80) NOT NULL,
    status emp_status DEFAULT 'active',
    hire_date DATE NOT NULL,
    salary NUMERIC(12,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE attendance_records (
    id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL REFERENCES employees(id),
    work_date DATE NOT NULL,
    check_in TIME,
    check_out TIME,
    late_minutes INT DEFAULT 0,
    remark VARCHAR(200),
    UNIQUE (employee_id, work_date)
);

CREATE TABLE leave_requests (
    id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL REFERENCES employees(id),
    leave_type leave_type NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    days NUMERIC(4,1) NOT NULL,
    status leave_status DEFAULT 'pending',
    reason TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE payrolls (
    id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL REFERENCES employees(id),
    period_month CHAR(7) NOT NULL,
    base_salary NUMERIC(12,2) NOT NULL,
    bonus NUMERIC(12,2) DEFAULT 0,
    deduction NUMERIC(12,2) DEFAULT 0,
    net_pay NUMERIC(12,2) NOT NULL,
    paid_at DATE,
    UNIQUE (employee_id, period_month)
);

CREATE TABLE training_courses (
    id SERIAL PRIMARY KEY,
    title VARCHAR(150) NOT NULL,
    category VARCHAR(50),
    hours INT DEFAULT 8,
    instructor VARCHAR(100),
    start_date DATE
);

CREATE TABLE training_enrollments (
    id SERIAL PRIMARY KEY,
    course_id INT NOT NULL REFERENCES training_courses(id),
    employee_id INT NOT NULL REFERENCES employees(id),
    score NUMERIC(5,2),
    completed BOOLEAN DEFAULT FALSE,
    enrolled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (course_id, employee_id)
);

CREATE TABLE performance_reviews (
    id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL REFERENCES employees(id),
    review_period CHAR(7) NOT NULL,
    score NUMERIC(4,1) NOT NULL,
    grade CHAR(1),
    reviewer VARCHAR(100),
    comments TEXT,
    UNIQUE (employee_id, review_period)
);

CREATE TABLE job_positions (
    id SERIAL PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    department_id INT REFERENCES departments(id),
    headcount INT DEFAULT 1,
    status VARCHAR(20) DEFAULT 'open',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE candidates (
    id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(120),
    position_id INT REFERENCES job_positions(id),
    stage VARCHAR(40) DEFAULT 'screening',
    source VARCHAR(40),
    applied_at DATE DEFAULT CURRENT_DATE
);

INSERT INTO departments (name, code, manager_name) VALUES
('总裁办', 'CEO', '王总'),
('技术中心', 'TECH', '李工'),
('安全运营', 'SEC', '赵安'),
('市场部', 'MKT', '钱销'),
('人力资源', 'HR', '孙人');

UPDATE departments SET parent_id = 1 WHERE id IN (2,3,4,5);

INSERT INTO employees (emp_no, full_name, email, phone, department_id, title, status, hire_date, salary) VALUES
('E001', '张三', 'zhangsan@rzx.demo', '13800000001', 2, '高级工程师', 'active', '2021-03-15', 22000),
('E002', '李四', 'lisi@rzx.demo', '13800000002', 2, '后端工程师', 'active', '2022-06-01', 18000),
('E003', '王五', 'wangwu@rzx.demo', '13800000003', 3, '安全分析师', 'active', '2020-11-20', 20000),
('E004', '赵六', 'zhaoliu@rzx.demo', '13800000004', 3, '安全运营专员', 'probation', '2025-12-01', 14000),
('E005', '钱七', 'qianqi@rzx.demo', '13800000005', 4, '市场经理', 'active', '2019-08-08', 19000),
('E006', '孙八', 'sunba@rzx.demo', '13800000006', 5, 'HRBP', 'active', '2021-01-10', 16000),
('E007', '周九', 'zhoujiu@rzx.demo', '13800000007', 2, '前端工程师', 'leave', '2023-04-18', 15000),
('E008', '吴十', 'wushi@rzx.demo', '13800000008', 4, '渠道专员', 'resigned', '2018-05-05', 12000);

INSERT INTO attendance_records (employee_id, work_date, check_in, check_out, late_minutes) VALUES
(1, '2026-03-24', '08:58', '18:05', 0),
(2, '2026-03-24', '09:12', '18:30', 12),
(3, '2026-03-24', '08:50', '19:10', 0),
(4, '2026-03-24', '09:20', '18:00', 20),
(5, '2026-03-24', '09:00', '18:00', 0),
(6, '2026-03-24', '08:55', '17:50', 0),
(1, '2026-03-25', '09:05', '18:20', 5),
(2, '2026-03-25', '08:59', '18:10', 0);

INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, days, status, reason) VALUES
(7, 'sick', '2026-03-20', '2026-03-22', 3, 'approved', '感冒发烧'),
(2, 'annual', '2026-04-01', '2026-04-03', 3, 'pending', '回家探亲'),
(5, 'personal', '2026-03-28', '2026-03-28', 1, 'approved', '办理证件'),
(3, 'annual', '2026-05-01', '2026-05-05', 5, 'pending', '五一休假');

INSERT INTO payrolls (employee_id, period_month, base_salary, bonus, deduction, net_pay, paid_at) VALUES
(1, '2026-02', 22000, 3000, 800, 24200, '2026-03-05'),
(2, '2026-02', 18000, 1500, 600, 18900, '2026-03-05'),
(3, '2026-02', 20000, 2000, 700, 21300, '2026-03-05'),
(5, '2026-02', 19000, 2500, 650, 20850, '2026-03-05'),
(6, '2026-02', 16000, 1000, 500, 16500, '2026-03-05');

INSERT INTO training_courses (title, category, hours, instructor, start_date) VALUES
('PostgreSQL 进阶', '技术', 16, '李工', '2026-02-10'),
('安全运营实战', '安全', 24, '赵安', '2026-02-18'),
('新员工入职培训', '综合', 8, '孙人', '2026-01-08'),
('大客户销售技巧', '市场', 12, '钱销', '2026-03-01');

INSERT INTO training_enrollments (course_id, employee_id, score, completed) VALUES
(1, 1, 92, TRUE),
(1, 2, 88, TRUE),
(2, 3, 95, TRUE),
(2, 4, 80, TRUE),
(3, 4, 90, TRUE),
(4, 5, 86, TRUE);

INSERT INTO performance_reviews (employee_id, review_period, score, grade, reviewer, comments) VALUES
(1, '2025-H2', 4.5, 'A', '李工', '技术扎实，带教积极'),
(2, '2025-H2', 4.0, 'B', '李工', '交付稳定'),
(3, '2025-H2', 4.6, 'A', '赵安', '应急处置出色'),
(5, '2025-H2', 4.2, 'B', '王总', '市场拓展有贡献'),
(6, '2025-H2', 4.1, 'B', '王总', '流程支持到位');

INSERT INTO job_positions (title, department_id, headcount, status) VALUES
('安全研发工程师', 3, 2, 'open'),
('数据分析师', 2, 1, 'open'),
('市场专员', 4, 1, 'closed');

INSERT INTO candidates (full_name, email, position_id, stage, source, applied_at) VALUES
('陈明', 'chenming@mail.demo', 1, 'interview', '猎头', '2026-03-01'),
('刘洋', 'liuyang@mail.demo', 1, 'screening', '官网', '2026-03-10'),
('黄晓', 'huangxiao@mail.demo', 2, 'offer', '内推', '2026-02-20'),
('郑凯', 'zhengkai@mail.demo', 3, 'hired', '招聘会', '2026-01-15');

-- ============================================================================
-- DATABASE: hospital_care
-- ============================================================================

DROP DATABASE IF EXISTS hospital_care;
CREATE DATABASE hospital_care;
\c hospital_care

CREATE TYPE gender_type AS ENUM ('male', 'female', 'unknown');
CREATE TYPE appt_status AS ENUM ('booked', 'checked_in', 'completed', 'cancelled', 'no_show');
CREATE TYPE order_status AS ENUM ('pending', 'paid', 'refunded');

CREATE TABLE departments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    floor VARCHAR(20),
    phone VARCHAR(30)
);

CREATE TABLE doctors (
    id SERIAL PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    title VARCHAR(50),
    department_id INT REFERENCES departments(id),
    specialty VARCHAR(100),
    years_experience INT DEFAULT 1,
    active BOOLEAN DEFAULT TRUE
);

CREATE TABLE patients (
    id SERIAL PRIMARY KEY,
    patient_no VARCHAR(30) UNIQUE NOT NULL,
    full_name VARCHAR(80) NOT NULL,
    gender gender_type DEFAULT 'unknown',
    birth_date DATE,
    phone VARCHAR(30),
    id_card VARCHAR(30),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE appointments (
    id SERIAL PRIMARY KEY,
    patient_id INT NOT NULL REFERENCES patients(id),
    doctor_id INT NOT NULL REFERENCES doctors(id),
    appt_time TIMESTAMP NOT NULL,
    status appt_status DEFAULT 'booked',
    chief_complaint VARCHAR(200),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE medical_records (
    id SERIAL PRIMARY KEY,
    patient_id INT NOT NULL REFERENCES patients(id),
    doctor_id INT NOT NULL REFERENCES doctors(id),
    appointment_id INT REFERENCES appointments(id),
    diagnosis VARCHAR(200) NOT NULL,
    treatment TEXT,
    visit_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE medicines (
    id SERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    spec VARCHAR(80),
    unit VARCHAR(20) DEFAULT '盒',
    unit_price NUMERIC(10,2) NOT NULL,
    stock INT DEFAULT 0
);

CREATE TABLE prescriptions (
    id SERIAL PRIMARY KEY,
    record_id INT NOT NULL REFERENCES medical_records(id),
    medicine_id INT NOT NULL REFERENCES medicines(id),
    quantity INT NOT NULL,
    dosage VARCHAR(100),
    amount NUMERIC(10,2) NOT NULL
);

CREATE TABLE wards (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    bed_count INT NOT NULL,
    department_id INT REFERENCES departments(id)
);

CREATE TABLE admissions (
    id SERIAL PRIMARY KEY,
    patient_id INT NOT NULL REFERENCES patients(id),
    ward_id INT NOT NULL REFERENCES wards(id),
    bed_no VARCHAR(20),
    admit_date DATE NOT NULL,
    discharge_date DATE,
    diagnosis VARCHAR(200)
);

CREATE TABLE billing_orders (
    id SERIAL PRIMARY KEY,
    patient_id INT NOT NULL REFERENCES patients(id),
    order_no VARCHAR(40) UNIQUE NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL,
    status order_status DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    paid_at TIMESTAMP
);

CREATE TABLE billing_items (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES billing_orders(id),
    item_name VARCHAR(120) NOT NULL,
    item_type VARCHAR(40),
    amount NUMERIC(12,2) NOT NULL
);

INSERT INTO departments (name, floor, phone) VALUES
('内科', '3F', '0755-8001'),
('外科', '4F', '0755-8002'),
('儿科', '2F', '0755-8003'),
('急诊科', '1F', '0755-8000'),
('骨科', '5F', '0755-8005');

INSERT INTO doctors (name, title, department_id, specialty, years_experience) VALUES
('周明', '主任医师', 1, '呼吸内科', 18),
('吴芳', '副主任医师', 1, '消化内科', 12),
('郑强', '主治医师', 2, '普外科', 9),
('冯丽', '主任医师', 3, '小儿呼吸', 15),
('陈波', '主治医师', 4, '急危重症', 10),
('韩雪', '副主任医师', 5, '关节外科', 11);

INSERT INTO patients (patient_no, full_name, gender, birth_date, phone) VALUES
('P1001', '何伟', 'male', '1988-02-14', '13900001001'),
('P1002', '罗敏', 'female', '1992-07-21', '13900001002'),
('P1003', '曹磊', 'male', '1975-11-03', '13900001003'),
('P1004', '邓悦', 'female', '2018-05-09', '13900001004'),
('P1005', '蒋涛', 'male', '1966-09-30', '13900001005'),
('P1006', '沈静', 'female', '1999-01-18', '13900001006'),
('P1007', '姚军', 'male', '1983-12-25', '13900001007'),
('P1008', '卢婷', 'female', '1995-04-02', '13900001008');

INSERT INTO appointments (patient_id, doctor_id, appt_time, status, chief_complaint) VALUES
(1, 1, '2026-03-26 09:00:00', 'completed', '咳嗽发热'),
(2, 2, '2026-03-26 09:30:00', 'completed', '胃痛'),
(3, 3, '2026-03-26 10:00:00', 'checked_in', '腹痛'),
(4, 4, '2026-03-26 10:30:00', 'booked', '发热咳嗽'),
(5, 6, '2026-03-26 14:00:00', 'booked', '膝盖疼痛'),
(6, 1, '2026-03-27 09:00:00', 'booked', '胸闷'),
(7, 5, '2026-03-25 20:10:00', 'completed', '外伤出血'),
(8, 2, '2026-03-27 11:00:00', 'cancelled', '复查');

INSERT INTO medical_records (patient_id, doctor_id, appointment_id, diagnosis, treatment, visit_date) VALUES
(1, 1, 1, '上呼吸道感染', '口服抗感染药物，多休息', '2026-03-26'),
(2, 2, 2, '慢性胃炎', '抑酸护胃，清淡饮食', '2026-03-26'),
(7, 5, 7, '手部外伤', '清创缝合，抗感染', '2026-03-25');

INSERT INTO medicines (name, spec, unit, unit_price, stock) VALUES
('阿莫西林胶囊', '0.25g*24粒', '盒', 18.50, 320),
('布洛芬缓释胶囊', '0.3g*20粒', '盒', 22.00, 210),
('奥美拉唑肠溶胶囊', '20mg*14粒', '盒', 28.80, 180),
('小儿氨酚黄那敏颗粒', '6g*10袋', '盒', 16.00, 150),
('碘伏消毒液', '100ml', '瓶', 12.00, 90);

INSERT INTO prescriptions (record_id, medicine_id, quantity, dosage, amount) VALUES
(1, 1, 2, '一日三次，一次两粒', 37.00),
(1, 2, 1, '疼痛时服用', 22.00),
(2, 3, 2, '一日一次，一次一粒', 57.60),
(3, 5, 1, '外用', 12.00),
(3, 1, 1, '一日三次', 18.50);

INSERT INTO wards (name, bed_count, department_id) VALUES
('内科一病区', 40, 1),
('外科一病区', 36, 2),
('儿科病区', 28, 3),
('骨科病区', 30, 5);

INSERT INTO admissions (patient_id, ward_id, bed_no, admit_date, discharge_date, diagnosis) VALUES
(5, 4, 'A-12', '2026-03-20', NULL, '半月板损伤观察'),
(3, 2, 'B-03', '2026-03-22', NULL, '腹痛待查'),
(1, 1, 'C-08', '2026-03-10', '2026-03-14', '肺炎恢复期');

INSERT INTO billing_orders (patient_id, order_no, total_amount, status, paid_at) VALUES
(1, 'BILL20260326001', 268.50, 'paid', '2026-03-26 10:20:00'),
(2, 'BILL20260326002', 186.00, 'paid', '2026-03-26 11:05:00'),
(7, 'BILL20260325001', 520.00, 'paid', '2026-03-25 21:00:00'),
(5, 'BILL20260326003', 1500.00, 'pending', NULL);

INSERT INTO billing_items (order_id, item_name, item_type, amount) VALUES
(1, '挂号费', '诊察', 25.00),
(1, '药品费', '药品', 59.00),
(1, '检查费', '检查', 184.50),
(2, '挂号费', '诊察', 25.00),
(2, '药品费', '药品', 57.60),
(2, '检查费', '检查', 103.40),
(3, '急诊处置', '治疗', 320.00),
(3, '药品费', '药品', 30.50),
(3, '材料费', '材料', 169.50),
(4, '住院预交', '住院', 1500.00);

-- ============================================================================
-- DATABASE: security_ops
-- ============================================================================

DROP DATABASE IF EXISTS security_ops;
CREATE DATABASE security_ops;
\c security_ops

CREATE TYPE asset_type AS ENUM ('server', 'network', 'endpoint', 'application', 'database');
CREATE TYPE severity_level AS ENUM ('info', 'low', 'medium', 'high', 'critical');
CREATE TYPE incident_status AS ENUM ('open', 'investigating', 'contained', 'resolved', 'closed');
CREATE TYPE alert_status AS ENUM ('new', 'ack', 'suppressed', 'closed');

CREATE TABLE organizations (
    id SERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    industry VARCHAR(60),
    region VARCHAR(60),
    contact_email VARCHAR(120)
);

CREATE TABLE assets (
    id SERIAL PRIMARY KEY,
    org_id INT NOT NULL REFERENCES organizations(id),
    asset_name VARCHAR(120) NOT NULL,
    asset_type asset_type NOT NULL,
    ip_address INET,
    criticality severity_level DEFAULT 'medium',
    owner VARCHAR(80),
    online BOOLEAN DEFAULT TRUE
);

CREATE TABLE sensors (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    sensor_type VARCHAR(50),
    location VARCHAR(100),
    status VARCHAR(20) DEFAULT 'online',
    last_heartbeat TIMESTAMP
);

CREATE TABLE alert_rules (
    id SERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    category VARCHAR(60),
    severity severity_level DEFAULT 'medium',
    enabled BOOLEAN DEFAULT TRUE,
    description TEXT
);

CREATE TABLE alerts (
    id SERIAL PRIMARY KEY,
    rule_id INT REFERENCES alert_rules(id),
    asset_id INT REFERENCES assets(id),
    title VARCHAR(200) NOT NULL,
    severity severity_level NOT NULL,
    status alert_status DEFAULT 'new',
    source VARCHAR(60),
    detected_at TIMESTAMP NOT NULL,
    ack_by VARCHAR(80),
    closed_at TIMESTAMP
);

CREATE TABLE incidents (
    id SERIAL PRIMARY KEY,
    incident_no VARCHAR(40) UNIQUE NOT NULL,
    title VARCHAR(200) NOT NULL,
    severity severity_level NOT NULL,
    status incident_status DEFAULT 'open',
    org_id INT REFERENCES organizations(id),
    assignee VARCHAR(80),
    opened_at TIMESTAMP NOT NULL,
    closed_at TIMESTAMP,
    summary TEXT
);

CREATE TABLE incident_alerts (
    incident_id INT NOT NULL REFERENCES incidents(id),
    alert_id INT NOT NULL REFERENCES alerts(id),
    PRIMARY KEY (incident_id, alert_id)
);

CREATE TABLE playbooks (
    id SERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    category VARCHAR(60),
    steps INT DEFAULT 1,
    owner VARCHAR(80),
    active BOOLEAN DEFAULT TRUE
);

CREATE TABLE playbook_runs (
    id SERIAL PRIMARY KEY,
    playbook_id INT NOT NULL REFERENCES playbooks(id),
    incident_id INT REFERENCES incidents(id),
    started_at TIMESTAMP NOT NULL,
    finished_at TIMESTAMP,
    result VARCHAR(40),
    operator VARCHAR(80)
);

CREATE TABLE vulnerability_findings (
    id SERIAL PRIMARY KEY,
    asset_id INT NOT NULL REFERENCES assets(id),
    cve_id VARCHAR(30),
    title VARCHAR(200) NOT NULL,
    severity severity_level NOT NULL,
    status VARCHAR(30) DEFAULT 'open',
    discovered_at DATE NOT NULL,
    fixed_at DATE
);

CREATE TABLE audit_events (
    id SERIAL PRIMARY KEY,
    actor VARCHAR(80) NOT NULL,
    action VARCHAR(80) NOT NULL,
    object_type VARCHAR(60),
    object_id VARCHAR(60),
    detail TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE threat_intel (
    id SERIAL PRIMARY KEY,
    ioc_type VARCHAR(30) NOT NULL,
    ioc_value VARCHAR(200) NOT NULL,
    threat_type VARCHAR(60),
    confidence INT DEFAULT 70,
    source VARCHAR(80),
    first_seen DATE,
    last_seen DATE
);

INSERT INTO organizations (name, industry, region, contact_email) VALUES
('深圳某制造集团', '制造', '华南', 'sec@mfg.demo'),
('某市教育局', '教育', '华南', 'soc@edu.demo'),
('华南某银行分行', '金融', '华南', 'csirt@bank.demo'),
('某三甲医院', '医疗', '华南', 'itsec@hosp.demo');

INSERT INTO assets (org_id, asset_name, asset_type, ip_address, criticality, owner, online) VALUES
(1, 'ERP-APP-01', 'application', '10.10.1.11', 'high', '运维一组', TRUE),
(1, '核心交换机-A', 'network', '10.10.0.1', 'critical', '网络组', TRUE),
(1, '办公终端-088', 'endpoint', '10.10.20.88', 'low', '员工张某', TRUE),
(2, '学籍系统', 'application', '10.20.1.5', 'high', '信息中心', TRUE),
(2, '边界防火墙', 'network', '10.20.0.2', 'critical', '信息中心', TRUE),
(3, '核心交易DB', 'database', '10.30.3.10', 'critical', '数仓组', TRUE),
(3, '网银前置', 'application', '10.30.2.8', 'critical', '应用组', TRUE),
(4, 'HIS 系统', 'application', '10.40.1.3', 'high', '医院信息科', TRUE),
(4, 'PACS 存储', 'server', '10.40.5.2', 'high', '医院信息科', FALSE);

INSERT INTO sensors (name, sensor_type, location, status, last_heartbeat) VALUES
('流量探针-出口', 'NTA', '机房A', 'online', '2026-03-26 10:00:00'),
('终端EDR-集群', 'EDR', '办公网', 'online', '2026-03-26 10:01:00'),
('日志采集器-1', 'Log', '机房B', 'degraded', '2026-03-26 09:40:00'),
('蜜罐节点-东区', 'Honeypot', '东区机房', 'online', '2026-03-26 09:58:00');

INSERT INTO alert_rules (name, category, severity, enabled, description) VALUES
('异常外联检测', '网络', 'high', TRUE, '检测到非常规外联行为'),
('暴力破解登录', '身份', 'medium', TRUE, '短时间多次失败登录'),
('勒索特征文件', '终端', 'critical', TRUE, '发现疑似勒索加密行为'),
('敏感数据外发', '数据', 'high', TRUE, '敏感文件异常外传'),
('漏洞利用尝试', '威胁', 'high', TRUE, '匹配已知 exploit 特征');

INSERT INTO alerts (rule_id, asset_id, title, severity, status, source, detected_at, ack_by, closed_at) VALUES
(1, 2, '核心交换机异常外联', 'high', 'ack', 'NTA', '2026-03-26 08:12:00', '赵安', NULL),
(2, 7, '网银前置暴力破解', 'medium', 'new', 'WAF', '2026-03-26 09:05:00', NULL, NULL),
(3, 3, '终端疑似勒索行为', 'critical', 'ack', 'EDR', '2026-03-25 22:18:00', '李工', NULL),
(4, 4, '学籍数据批量导出', 'high', 'new', 'DLP', '2026-03-26 09:40:00', NULL, NULL),
(5, 6, '交易库漏洞利用探测', 'high', 'closed', 'IDS', '2026-03-24 16:20:00', '赵安', '2026-03-24 18:00:00'),
(1, 5, '防火墙策略变更后外联激增', 'medium', 'suppressed', 'NTA', '2026-03-23 11:00:00', '网络组', '2026-03-23 12:00:00'),
(2, 1, 'ERP 管理账号失败登录过多', 'medium', 'closed', 'IAM', '2026-03-22 08:30:00', '运维一组', '2026-03-22 09:10:00'),
(4, 8, '病历附件外发告警', 'high', 'new', 'DLP', '2026-03-26 10:05:00', NULL, NULL);

INSERT INTO incidents (incident_no, title, severity, status, org_id, assignee, opened_at, closed_at, summary) VALUES
('INC-20260325-001', '办公终端勒索事件', 'critical', 'investigating', 1, '赵安', '2026-03-25 22:20:00', NULL, 'EDR 检出加密行为，已隔离终端'),
('INC-20260326-002', '学籍数据疑似泄露排查', 'high', 'open', 2, '李工', '2026-03-26 09:45:00', NULL, 'DLP 告警触发，核查导出账号'),
('INC-20260324-003', '交易库扫描行为', 'high', 'resolved', 3, '赵安', '2026-03-24 16:25:00', '2026-03-24 19:00:00', '确认为授权渗透测试'),
('INC-20260320-004', '边界策略误配导致异常流量', 'medium', 'closed', 2, '网络组', '2026-03-20 10:00:00', '2026-03-21 15:00:00', '回滚策略后恢复');

INSERT INTO incident_alerts (incident_id, alert_id) VALUES
(1, 3),
(2, 4),
(2, 8),
(3, 5),
(4, 6);

INSERT INTO playbooks (name, category, steps, owner, active) VALUES
('终端隔离与取证', '终端安全', 6, '安全运营', TRUE),
('数据泄露应急响应', '数据安全', 8, '安全运营', TRUE),
('漏洞利用应急处置', '威胁响应', 5, '攻防组', TRUE),
('暴力破解封禁流程', '身份安全', 4, '安全运营', TRUE);

INSERT INTO playbook_runs (playbook_id, incident_id, started_at, finished_at, result, operator) VALUES
(1, 1, '2026-03-25 22:25:00', '2026-03-25 23:10:00', 'success', '赵安'),
(2, 2, '2026-03-26 09:50:00', NULL, 'running', '李工'),
(3, 3, '2026-03-24 16:40:00', '2026-03-24 18:20:00', 'success', '赵安'),
(4, 3, '2026-03-24 17:00:00', '2026-03-24 17:30:00', 'success', '值班员');

INSERT INTO vulnerability_findings (asset_id, cve_id, title, severity, status, discovered_at, fixed_at) VALUES
(6, 'CVE-2024-1234', '数据库远程代码执行风险', 'critical', 'open', '2026-03-01', NULL),
(7, 'CVE-2023-9876', '中间件反序列化漏洞', 'high', 'fixed', '2026-02-12', '2026-02-28'),
(1, 'CVE-2024-5555', '组件过期存在 XSS', 'medium', 'open', '2026-03-10', NULL),
(5, 'CVE-2022-1111', '防火墙固件高危漏洞', 'high', 'accepted', '2026-01-20', NULL),
(8, 'CVE-2024-2222', 'Web 框架权限绕过', 'high', 'open', '2026-03-18', NULL);

INSERT INTO audit_events (actor, action, object_type, object_id, detail) VALUES
('赵安', 'ack_alert', 'alert', '1', '确认交换机外联告警'),
('李工', 'create_incident', 'incident', 'INC-20260326-002', '由 DLP 告警升级事件'),
('值班员', 'run_playbook', 'playbook', '4', '执行暴力破解封禁'),
('系统', 'sensor_degraded', 'sensor', '3', '日志采集器心跳延迟'),
('王总', 'export_report', 'report', 'weekly', '导出周报');

INSERT INTO threat_intel (ioc_type, ioc_value, threat_type, confidence, source, first_seen, last_seen) VALUES
('ip', '203.0.113.66', 'C2', 90, '内部情报', '2026-03-01', '2026-03-25'),
('domain', 'evil-update.demo', 'malware', 85, '开源情报', '2026-02-18', '2026-03-20'),
('hash', 'd41d8cd98f00b204e9800998ecf8427e', 'ransomware', 80, 'EDR', '2026-03-25', '2026-03-25'),
('ip', '198.51.100.23', 'scan', 60, '蜜罐', '2026-03-10', '2026-03-26'),
('url', 'http://phish.demo/login', 'phishing', 75, '邮件网关', '2026-03-15', '2026-03-22');
