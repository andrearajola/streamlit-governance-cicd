"""Sales by country - FINANCE (restricted caller's rights).

Rows come from TEST_DATA_FINANCE.GOLD.SALES, which has a row access policy by country.
With caller's rights the policy is evaluated for the VIEWER (their default role), so each
analyst only sees their countries. The owner's-rights query is shown for comparison.
"""
import streamlit as st

st.set_page_config(page_title="Sales by country", layout="wide")

# Caller's rights: open at the top of the script (the viewer token is only valid for 2 minutes)
callers = st.connection("snowflake-callers-rights")
owner = st.connection("snowflake")

SALES_SQL = "SELECT country, month, amount FROM TEST_DATA_FINANCE.GOLD.SALES ORDER BY country, month"


@st.cache_data(ttl=300, scope="session")  # session scope: never share one viewer's rows with another
def load_sales_as_viewer():
    return callers.query(SALES_SQL)


st.title("Sales by country")
who = callers.query("SELECT CURRENT_USER() AS user_name, CURRENT_ROLE() AS role_name")
st.caption(f"Viewer: {who.iloc[0]['USER_NAME']} | role used for the data: {who.iloc[0]['ROLE_NAME']}")

sales = load_sales_as_viewer()
col1, col2 = st.columns(2)
col1.metric("Countries you can see", sales["COUNTRY"].nunique())
col2.metric("Total amount", f"{sales['AMOUNT'].sum():,.0f}")
st.bar_chart(sales, x="MONTH", y="AMOUNT", color="COUNTRY")
st.dataframe(sales, hide_index=True)

with st.expander("Why caller's rights? (owner's rights comparison)"):
    owner_rows = owner.query("SELECT COUNT(*) AS n FROM TEST_DATA_FINANCE.GOLD.SALES")
    st.write(
        f"The same table read with the app OWNER role returns {int(owner_rows.iloc[0]['N'])} rows: "
        "the row access policy sees the owner role, not you."
    )
