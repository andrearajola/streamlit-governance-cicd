import streamlit as st
from snowflake.snowpark.context import get_active_session

password = "Verisure2026!"


def get_conn():
    return st.connection("snowflake-callers-rights")


@st.cache_data(ttl=60)
def load():
    return get_conn().query("SELECT * FROM TEST_DATA_FINANCE.GOLD.SALES")


st.title("Budget tracker")
st.dataframe(load())
