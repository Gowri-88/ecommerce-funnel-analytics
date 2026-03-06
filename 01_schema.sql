-- ============================================================
-- E-Commerce Analytics — Database Schema
-- Creates the ecom_analytics database and all 6 tables
-- Run this first before loading any data
-- ============================================================

CREATE DATABASE IF NOT EXISTS ecom_analytics;
USE ecom_analytics;

-- ── USERS ────────────────────────────────────────────────────
-- One row per user — acquisition channel, device, signup date
CREATE TABLE IF NOT EXISTS users (
    user_id       VARCHAR(20)  PRIMARY KEY,
    signup_date   DATE         NOT NULL,
    channel       VARCHAR(30)  NOT NULL,
    device_type   VARCHAR(20)  NOT NULL,
    country       VARCHAR(50)  DEFAULT 'India'
);

-- ── SESSIONS ─────────────────────────────────────────────────
-- One row per browsing session — links user to session events
CREATE TABLE IF NOT EXISTS sessions (
    session_id    VARCHAR(20)  PRIMARY KEY,
    user_id       VARCHAR(20)  NOT NULL,
    session_date  DATE         NOT NULL,
    channel       VARCHAR(30)  NOT NULL,
    device_type   VARCHAR(20)  NOT NULL,
    duration_sec  INT          DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- ── EVENTS ───────────────────────────────────────────────────
-- Every user action — visit, product view, cart, checkout, purchase
CREATE TABLE IF NOT EXISTS events (
    event_id      VARCHAR(20)  PRIMARY KEY,
    user_id       VARCHAR(20)  NOT NULL,
    session_id    VARCHAR(20),
    event_type    VARCHAR(30)  NOT NULL,
    event_ts      DATETIME     NOT NULL,
    channel       VARCHAR(30)  NOT NULL,
    device_type   VARCHAR(20)  NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- ── ORDERS ───────────────────────────────────────────────────
-- Every completed purchase with revenue, channel, coupon info
CREATE TABLE IF NOT EXISTS orders (
    order_id       VARCHAR(20)  PRIMARY KEY,
    user_id        VARCHAR(20)  NOT NULL,
    order_ts       DATETIME     NOT NULL,
    total_amount   DECIMAL(10,2) NOT NULL,
    channel        VARCHAR(30)  NOT NULL,
    device_type    VARCHAR(20)  NOT NULL,
    coupon_used    TINYINT(1)   DEFAULT 0,
    coupon_code    VARCHAR(20),
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- ── ORDER ITEMS ───────────────────────────────────────────────
-- Line items per order — product, category, price, quantity
CREATE TABLE IF NOT EXISTS order_items (
    item_id       VARCHAR(20)  PRIMARY KEY,
    order_id      VARCHAR(20)  NOT NULL,
    product_id    VARCHAR(20)  NOT NULL,
    category      VARCHAR(30)  NOT NULL,
    unit_price    DECIMAL(10,2) NOT NULL,
    quantity      INT          NOT NULL DEFAULT 1,
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

-- ── AD SPEND ─────────────────────────────────────────────────
-- Daily advertising spend per channel — used for ROAS calculation
CREATE TABLE IF NOT EXISTS ad_spend (
    spend_id      INT          PRIMARY KEY AUTO_INCREMENT,
    spend_date    DATE         NOT NULL,
    channel       VARCHAR(30)  NOT NULL,
    spend_usd     DECIMAL(10,2) NOT NULL
);
