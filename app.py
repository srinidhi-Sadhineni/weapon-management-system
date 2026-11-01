import streamlit as st
import mysql.connector
import pandas as pd

st.set_page_config(
    page_title="Weapon Management System",
    page_icon="🛡️",
    layout="wide"
)

st.title("Weapon Management System")
st.caption("DBMS Mini Project | MySQL + Streamlit")

# Database connection settings
st.sidebar.header("MySQL Connection")

host = st.secrets["DB_HOST"]
user = st.secrets["DB_USERNAME"]
password = st.secrets["DB_PASSWORD"]
port = int(st.secrets["DB_PORT"])
database = st.secrets["DB_NAME"]

@st.cache_data(ttl=10)
def load_data(query, host, user, password, port, database):
    conn = mysql.connector.connect(
    host=st.secrets["DB_HOST"],
    port=int(st.secrets["DB_PORT"]),
    user=st.secrets["DB_USERNAME"],
    password=st.secrets["DB_PASSWORD"],
    database=st.secrets["DB_NAME"],
    ssl_ca="ca.pem",
    ssl_verify_cert=True
)
    try:
        return pd.read_sql(query, conn)
    finally:
        conn.close()

page = st.sidebar.selectbox(
    "Select Section",
    [
        "Dashboard",
        "Admin",
        "Category",
        "Storage",
        "Personnel",
        "Weapon Inventory",
        "Weapon Allocation",
        "Maintenance",
        "Allocation Audit Log",
        "Active Allocations",
        "Overdue Allocations",
        "Inventory Summary"
    ]
)

queries = {
    "Admin": """
        SELECT admin_id, username, full_name, email,
               role, created_at
        FROM Admin
    """,
    "Category": "SELECT * FROM Category",
    "Storage": "SELECT * FROM Storage",
    "Personnel": "SELECT * FROM Personnel",
    "Weapon Inventory": """
        SELECT w.weapon_id, w.weapon_name, w.serial_number,
               c.category_name, s.storage_location,
               w.condition_status, w.status
        FROM Weapon w
        JOIN Category c ON w.category_id = c.category_id
        JOIN Storage s ON w.storage_id = s.storage_id
    """,
    "Weapon Allocation": """
        SELECT allocation_id, weapon_id, personnel_id,
               admin_id, issue_date, expected_return_date,
               actual_return_date, purpose, approval_status,
               remarks
        FROM Weapon_Allocation
    """,
    "Maintenance": "SELECT * FROM Maintenance",
    "Allocation Audit Log": "SELECT * FROM Allocation_Audit_Log",
    "Active Allocations": "SELECT * FROM vw_active_allocations",
    "Overdue Allocations": "SELECT * FROM vw_overdue_allocations",
    "Inventory Summary": "SELECT * FROM vw_weapon_inventory_summary"
}

if st.sidebar.button("Connect to MySQL"):
    st.session_state["db_connected"] = True

if st.session_state.get("db_connected", False):
    try:
        if page == "Dashboard":
            st.subheader("Database Dashboard")

            counts = {}
            tables = [
                "Admin", "Category", "Storage", "Personnel",
                "Weapon", "Weapon_Allocation", "Maintenance",
                "Allocation_Audit_Log"
            ]

            for table in tables:
                df = load_data(
    f"SELECT COUNT(*) AS total FROM `{table}`",
    host, user, password, port, database
)
                
                counts[table] = int(df.iloc[0]["total"])

            c1, c2, c3 = st.columns(3)
            c1.metric("Weapons", counts["Weapon"])
            c2.metric("Personnel", counts["Personnel"])
            c3.metric("Categories", counts["Category"])

            c4, c5, c6 = st.columns(3)
            c4.metric("Allocations", counts["Weapon_Allocation"])
            c5.metric("Maintenance Records", counts["Maintenance"])
            c6.metric("Audit Log Entries", counts["Allocation_Audit_Log"])

            st.subheader("Weapon Status Summary")
            status_df = load_data(
                """
                SELECT status, COUNT(*) AS total
                FROM Weapon
                GROUP BY status
                """,
                host, user, password, port, database
            )
            st.dataframe(status_df, use_container_width=True)

            st.subheader("Weapon Condition Summary")
            condition_df = load_data(
                """
                SELECT condition_status, COUNT(*) AS total
                FROM Weapon
                GROUP BY condition_status
                """,
               host, user, password, port, database
            )
            st.dataframe(condition_df, use_container_width=True)

        else:
            st.subheader(page)

            df = load_data(
                queries[page], host, user, password, port, database
            )
            st.metric("Records Found", len(df))
            st.dataframe(df, use_container_width=True)

            if not df.empty:
                csv = df.to_csv(index=False).encode("utf-8")
                st.download_button(
                    "Download CSV",
                    data=csv,
                    file_name=f"{page.lower().replace(' ', '_')}.csv",
                    mime="text/csv"
                )

    except mysql.connector.Error as e:
        st.error(f"MySQL connection or query error: {e}")
        st.info(
            "Check that MySQL is running, the database exists, "
            "and your username and password are correct."
        )
    except Exception as e:
        st.error(f"Error: {e}")

else:
    st.info(
        "Enter your MySQL credentials in the sidebar "
        "and click Connect to MySQL."
    )
