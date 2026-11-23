"""Margin by country - FINANCE (restricted caller's rights): each viewer sees only their countries."""
import streamlit as st

st.set_page_config(page_title="Margin by country", layout="wide")
callers = st.connection("snowflake-callers-rights")   # top of the script (viewer token lasts 2 minutes)


@st.cache_data(ttl=60, scope="session")
def load():
    return callers.query(
        "SELECT country, SUM(amount) AS sales, ROUND(SUM(amount) * 0.3, 2) AS margin "
        "FROM TEST_DATA_FINANCE.GOLD.SALES GROUP BY country ORDER BY country"
    )


st.title("Margin by country")
st.dataframe(load(), hide_index=True)
