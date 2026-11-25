"""Verisure permissions test: owner's rights app on the shared system compute pool, no PyPI access."""
import streamlit as st

st.set_page_config(page_title="Verisure sim", layout="wide")
conn = st.connection("snowflake")

st.title("Verisure permissions test")
st.dataframe(conn.query("SELECT COUNTRY, SUM(AMOUNT) AS SALES FROM DB_VERISURE_SIM.DEMO_DATA.SALES GROUP BY COUNTRY ORDER BY COUNTRY"), hide_index=True)
