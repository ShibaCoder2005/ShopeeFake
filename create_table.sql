CREATE TABLE Categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);

CREATE TABLE Users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    address TEXT,
    phone VARCHAR(20) UNIQUE,
    full_name VARCHAR(100),
    role VARCHAR(20) NOT NULL, 
    locked BOOLEAN DEFAULT FALSE
);

CREATE TABLE Admin (
    admin_id SERIAL PRIMARY KEY,
    user_id INT UNIQUE REFERENCES Users(user_id) ON DELETE CASCADE,
    bank_account_number VARCHAR(50),
    bank_account_name VARCHAR(100),
    qr_img_path VARCHAR(255)
);

CREATE TABLE Sellers (
    seller_id SERIAL PRIMARY KEY,
    user_id INT UNIQUE REFERENCES Users(user_id) ON DELETE CASCADE,
    store_name VARCHAR(100) NOT NULL,
    description TEXT,
    qr_img_path VARCHAR(255)
);

CREATE TABLE Shipping_units (
    shipping_units_id SERIAL PRIMARY KEY,
    user_id INT UNIQUE REFERENCES Users(user_id) ON DELETE CASCADE,
    company_name VARCHAR(100) NOT NULL
);

CREATE TABLE Carts (
    cart_id SERIAL PRIMARY KEY,
    user_id INT UNIQUE REFERENCES Users(user_id) ON DELETE CASCADE
);

CREATE TABLE Products (
    product_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(12, 2) NOT NULL,
    description TEXT,
    stock INT DEFAULT 0,
    img_path VARCHAR(255),
    visible BOOLEAN DEFAULT TRUE,
    seller_id INT REFERENCES Sellers(seller_id) ON DELETE CASCADE
);

CREATE TABLE Orders (
    order_id SERIAL PRIMARY KEY,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50), 
    tracking_number VARCHAR(100),
    shipping_status VARCHAR(50),
    estimated_delivery TIMESTAMP,
    payment_id VARCHAR(100),
    payment_date TIMESTAMP,
    payment_method VARCHAR(50),
    amount DECIMAL(12, 2),
    payment_status VARCHAR(50), 
    user_id INT REFERENCES Users(user_id) ON DELETE SET NULL, 
    seller_id INT REFERENCES Sellers(seller_id) ON DELETE SET NULL,
    shipping_units_id INT REFERENCES Shipping_units(shipping_units_id) ON DELETE SET NULL
);

CREATE TABLE Product_categories (
    product_id INT REFERENCES Products(product_id) ON DELETE CASCADE,
    category_id INT REFERENCES Categories(category_id) ON DELETE CASCADE,
    PRIMARY KEY (product_id, category_id)
);

CREATE TABLE Cart_items (
    cart_id INT REFERENCES Carts(cart_id) ON DELETE CASCADE,
    product_id INT REFERENCES Products(product_id) ON DELETE CASCADE,
    quantity INT NOT NULL DEFAULT 1,
    PRIMARY KEY (cart_id, product_id)
);

CREATE TABLE Order_Items (
    order_id INT REFERENCES Orders(order_id) ON DELETE CASCADE,
    product_id INT REFERENCES Products(product_id) ON DELETE NO ACTION,
    quantity INT NOT NULL CHECK (quantity > 0),
    comment TEXT,
    rating INT CHECK (rating >= 1 AND rating <= 5),
    PRIMARY KEY (order_id, product_id)
);