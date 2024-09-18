-- Query in progress 9/18/24
-- TracRite>Optimum Control Inventory Measurement Tool
-- Output:
    -- Item Description, Internal Item ID, Recent Supplier, 
    -- Supplier Order Code, Inv. Category Name, Item Storage 
    -- Location, Reporting UOM, Opening Inv, Purchase Qty, 
    -- X-Fer In Qty, X-Fer Out Qty, Waste Qty, Ending Inv Qty, 
    -- Usage Qty. Purchase Value, End Inv. Value

-- Store ID Values
  -- 8	Banquets
  -- 1	Cabinet
  -- 7	C-Rock
  -- 3	Crow's Ben
  -- 13	Gourmandie
  -- 9	Lakeview
  -- 14	Mojo
  -- 12	Outback
  -- 2	Warehouse
  -- 11	Rowdy
  -- 4	Sky House
  -- 10	Taps
  
-- Set transaction isolation level and prevent extra result sets
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET NOCOUNT ON;

-- Declare variables to filter the data
DECLARE @Store SMALLINT = 2;               -- Store identifier for filtering the data
DECLARE @StartDate DATETIME = '2024-08-01'; -- Start date for the reporting period
DECLARE @EndDate DATETIME = '2024-08-31';   -- End date for the reporting period

-- Declare a temporary table to hold the summary data
DECLARE @UsageSummary TABLE (
    ItemId SMALLINT,               -- Item Identifier from Optimum Control
    ItemDescrip NVARCHAR(50),      -- Item Description
    Supplier NVARCHAR(100),        -- Supplier Name
    OrderCode NVARCHAR(50),        -- Order Code
    Category_Name NVARCHAR(50),    -- Category Name
    Item_Location NVARCHAR(50),    -- Primary Location Name
    UOM NVARCHAR(17),              -- Unit of Measure
    OpenInvQty DECIMAL(14, 3),     -- Opening Inventory Quantity
    PurchaseQty DECIMAL(14, 3),    -- Period Purchase Quantity
    TransferOutQty DECIMAL(14, 3), -- Transfer Out Quantity
    TransferInQty DECIMAL(14, 3),  -- Transfer In Quantity
    WasteQty DECIMAL(14, 3),       -- Waste Quantity
    EndInvQty DECIMAL(14, 3),      -- Ending Inventory Quantity
    UsageQty DECIMAL(14, 3),       -- Actual Usage Quantity
    ApproxValue DECIMAL(15, 4),    -- Approximate Value (calculated using average cost)
    EndInvValue DECIMAL(15, 4)     -- Ending Inventory Value
);

-- Insert data into the temporary table from various inventory and item-related tables
INSERT INTO @UsageSummary
SELECT 
    i.ItemId,                            -- Adjust to correct column name from TOC
    i.Descrip AS ItemDescrip,
    si.SupplierName,                     -- Correct this based on actual supplier table column
    si.OrderCode,                        -- Correct OrderCode column based on actual table
    c.Name AS Category_Name,
    l.Name AS Item_Location,
    u.Descrip AS UOM,
    COALESCE(insu_open.QtyOnHand, 0) / icf.ReportingConversionFactor 
    + COALESCE(insu_open.PreppedQty, 0) / icf.ReportingConversionFactor AS OpenInvQty,
    COALESCE(ui.InvoiceSum, 0) / icf.ReportingConversionFactor AS PurchaseQty,
    COALESCE(tout.TransferOutQty, 0) / icf.ReportingConversionFactor AS TransferOutQty,
    COALESCE(tin.TransferInQty, 0) / icf.ReportingConversionFactor AS TransferInQty,
    COALESCE(waste.WasteQty, 0) / icf.ReportingConversionFactor AS WasteQty,
    COALESCE(insu_close.QtyOnHand, 0) / icf.ReportingConversionFactor 
    + COALESCE(insu_close.PreppedQty, 0) / icf.ReportingConversionFactor AS EndInvQty,
    (COALESCE(insu_open.QtyOnHand, 0) / icf.ReportingConversionFactor 
    + COALESCE(insu_open.PreppedQty, 0) / icf.ReportingConversionFactor 
    + COALESCE(ui.InvoiceSum, 0) / icf.ReportingConversionFactor 
    + COALESCE(tout.TransferOutQty, 0) / icf.ReportingConversionFactor 
    + COALESCE(tin.TransferInQty, 0) / icf.ReportingConversionFactor 
    + COALESCE(waste.WasteQty, 0) / icf.ReportingConversionFactor) 
    - (COALESCE(insu_close.QtyOnHand, 0) / icf.ReportingConversionFactor 
    + COALESCE(insu_close.PreppedQty, 0) / icf.ReportingConversionFactor) AS UsageQty,
    (COALESCE(insu_open.TotalValue, 0) + COALESCE(ui.InvoiceValue, 0) 
    - COALESCE(insu_close.TotalValue, 0)) AS ApproxValue,
    COALESCE(insu_close.TotalValue, 0) AS EndInvValue
FROM 
    oc.Item i
    -- Join with Category table to fetch Category Name
    LEFT JOIN oc.[Group] g ON g.GroupId = i.ItemGroup
    LEFT JOIN oc.Category c ON c.CategoryId = g.Category 

    -- Join with KeyItemDetail table to fetch Primary Location based on the Store
    LEFT JOIN oc.KeyItemDetail kid ON kid.Item = i.ItemId AND kid.Store = @Store
    LEFT JOIN oc.Location l ON l.LocationId = kid.PrimaryLocation

-- Supplier Information: Get the most recent OrderCode and Supplier for each item from CaseSize
LEFT JOIN (
    SELECT
        cs.Item,                                 -- Item identifier from CaseSize
        s.Name AS SupplierName,                  -- Fetching Supplier Name from Supplier table
        cs.OrderCode,                            -- Order code from CaseSize table
        ROW_NUMBER() OVER (PARTITION BY cs.Item ORDER BY i.InvoiceDate DESC) AS rn  -- Ranking to get the most recent supplier/order code
    FROM oc.CaseSize cs
    JOIN oc.InvoiceItem ii ON ii.Item = cs.Item  -- Joining InvoiceItem to tie invoices to items
    JOIN oc.Invoice i ON i.InvoiceId = ii.Invoice  -- Joining Invoice table to get InvoiceDate and Supplier
    JOIN oc.Supplier s ON s.SupplierId = i.Supplier  -- Joining Supplier to fetch supplier name based on SupplierId from Invoice
    WHERE ISNUMERIC(LEFT(s.Name, 1)) = 0  -- Exclude internal suppliers whose names start with a number
) si ON si.Item = i.ItemId AND si.rn = 1  -- Only get the most recent record per item

    -- Join with Inventory Summary for Opening Inventory
    LEFT JOIN oc.Inventory inv_open ON inv_open.OpenDate = @StartDate AND inv_open.Store = @Store
    LEFT JOIN oc.InventorySummary insu_open ON inv_open.InventoryId = insu_open.Inventory 
    AND insu_open.Item = i.ItemId

    -- Join with Inventory Summary for Closing Inventory
    LEFT JOIN oc.Inventory inv_close ON inv_close.CloseDate = @EndDate AND inv_close.Store = @Store
    LEFT JOIN oc.InventorySummary insu_close ON inv_close.InventoryId = insu_close.Inventory 
    AND insu_close.Item = i.ItemId

    -- Join with Invoice data for Period Purchases
    LEFT JOIN (
        SELECT 
            ii.Item,
            i.Store,
            SUM(ii.StockQty - COALESCE(ir.StockQty, 0)) AS InvoiceSum,
            SUM(ii.AdjustedTotal) AS InvoiceValue
        FROM 
            oc.InvoiceItem ii
            JOIN oc.Invoice i ON i.InvoiceId = ii.Invoice 
            AND i.InvoiceDate BETWEEN @StartDate AND @EndDate
            LEFT JOIN oc.InvoiceRFC ir ON ii.InvoiceLineId = ir.InvoiceItem
        WHERE i.Store = @Store
        GROUP BY ii.Item, i.Store
    ) AS ui ON ui.Item = i.ItemId

    -- Transfer Out Data
    LEFT JOIN (
        SELECT 
            iu.Item, 
            SUM(-iu.StockQty) AS TransferOutQty
        FROM oc.ItemUsage iu
        JOIN oc.TransferContext tc ON tc.UsageSource = iu.UsageSource
        JOIN oc.[Transfer] t ON t.Sender = tc.TransferContextId
        WHERE t.TransferDate BETWEEN @StartDate AND @EndDate AND tc.Store = @Store
        GROUP BY iu.Item
    ) AS tout ON tout.Item = i.ItemId

    -- Transfer In Data
    LEFT JOIN (
        SELECT 
            iu.Item, 
            SUM(-iu.StockQty) AS TransferInQty
        FROM oc.ItemUsage iu
        JOIN oc.TransferContext tc ON tc.UsageSource = iu.UsageSource
        JOIN oc.[Transfer] t ON t.Receiver = tc.TransferContextId
        WHERE t.TransferDate BETWEEN @StartDate AND @EndDate AND tc.Store = @Store
        GROUP BY iu.Item
    ) AS tin ON tin.Item = i.ItemId

    -- Waste Data
    LEFT JOIN (
        SELECT 
            iu.Item, 
            SUM(-iu.StockQty) AS WasteQty
        FROM oc.ItemUsage iu
        JOIN oc.UsageSource us ON iu.UsageSource = us.UsageSourceId
        JOIN oc.Waste w ON w.UsageSource = iu.UsageSource
        WHERE w.WasteDate BETWEEN @StartDate AND @EndDate AND us.Store = @Store
        GROUP BY iu.Item
    ) AS waste ON waste.Item = i.ItemId

    -- Join with Unit of Measure to fetch correct UOM for reporting
    LEFT JOIN oc.ItemConversionFactor icf ON icf.Item = i.ItemId
    LEFT JOIN oc.Uom u ON u.UomId = icf.ReportingUom;

-- Select the data from the temporary table
SELECT 
    ItemId AS OC_ItemID,
    ItemDescrip,
    Supplier,
    OrderCode,
    Category_Name,
    Item_Location,
    UOM,
    OpenInvQty,
    PurchaseQty,
    TransferOutQty,
    TransferInQty,
    WasteQty,
    EndInvQty,
    UsageQty,
    ApproxValue AS Ave_Cost,
    EndInvValue AS End_Inv_Value
FROM @UsageSummary
WHERE 
    (OpenInvQty <> 0 OR PurchaseQty <> 0 OR TransferOutQty <> 0 OR 
     TransferInQty <> 0 OR WasteQty <> 0 OR EndInvQty <> 0)
ORDER BY 
    Category_Name, 
    ItemDescrip;

-- Reset transaction isolation level
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET NOCOUNT OFF;
