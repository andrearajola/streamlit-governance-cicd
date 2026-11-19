"""Budget tracker - FINANCE (restricted caller's rights): actuals per country, filtered by the viewer's role."""
import streamlit as st

st.set_page_config(page_title="Budget tracker", layout="wide")
callers = st.connection("snowflake-callers-rights")   # top of the script (viewer token lasts 2 minutes)


@st.cache_data(ttl=60, scope="session")
def load():
    return callers.query(
        "SELECT country, SUM(amount) AS actual FROM TEST_DATA_FINANCE.GOLD.SALES GROUP BY country ORDER BY country"
    )


st.title("Budget tracker")
actuals = load()
budget = st.number_input("Monthly budget per country", min_value=0, value=1000, step=100)
actuals["BUDGET"] = budget * 2
actuals["VS_BUDGET"] = actuals["ACTUAL"] - actuals["BUDGET"]
st.dataframe(actuals, hide_index=True)
