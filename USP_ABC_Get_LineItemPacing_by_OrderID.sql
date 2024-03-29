USE [SageBizOps]
GO
/****** Object:  StoredProcedure [dbo].[USP_ABC_Get_LineItemPacing_by_OrderID]    Script Date: 06/18/2014 11:49:54 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[USP_ABC_Get_LineItemPacing_by_OrderID]

	 @NewProposalId	INT 
	
AS



/*

DECLARE @NewProposalId	INT 
SET		@NewProposalId	=	4328914

*/


------------------------------------------------------------------------
-- 1. The tables in denormalized so we need to do this in different way.
------------------------------------------------------------------------
------------------------------------------------------------------------
-- [NewProposalId] AND 
-- Lowest level is [External or Embedded Campaign Id] Get the SUM(Impressions).
------------------------------------------------------------------------


SELECT	ABCAdjusterDashboard.[Order Id], 
		ABCAdjusterDashboard.[Campaign Identifier], 
		[Campaign Name], 
		[Local Server],
		[Local Server Name],
		[Embedded Campaign Id],
		SUM([Clicks])								AS sumClicks,
		SUM([Clicks (3rd Party)])					AS sumClicks3rdParty,
		SUM([Impressions])							AS sumImpressions, 
		SUM(ISNULL([Impressions (3rd Party)],0))	AS sumImpressions3ps
INTO #AllProposalID
FROM ABCAdjusterDashboard 
INNER JOIN ( 
			SELECT	[Order Id], 
					[Campaign Identifier], 	
					[MinCampaign Start]		= MIN([Campaign Start]),
					[MaxCampaign End]		= MAX([Campaign End])
			FROM ABCAdjusterDashboard
			WHERE	ABCAdjusterDashboard.[Order Id]		=	@NewProposalId AND 
					[Billable Creative] IS NULL
			GROUP BY 
					[Order Id], 
					[Campaign Identifier]
			) MinMaxInfo ON 
			ABCAdjusterDashboard.[Order Id]				= MinMaxInfo.[Order Id]				AND 
			ABCAdjusterDashboard.[Campaign Identifier]	= MinMaxInfo.[Campaign Identifier]	AND 
			ABCAdjusterDashboard.[Report Data Date]		>= MinMaxInfo.[MinCampaign Start]	AND 
			ABCAdjusterDashboard.[Report Data Date]		<= MinMaxInfo.[MaxCampaign End]					
			
WHERE	ABCAdjusterDashboard.[Order Id]		=	@NewProposalId AND 
		[Billable Creative] IS NULL  		
GROUP BY 
		ABCAdjusterDashboard.[Order Id], 
		ABCAdjusterDashboard.[Campaign Identifier], 
		[Campaign Name], 
		[Local Server],
		[Local Server Name],
		[Embedded Campaign Id] 


 -- SELECT * FROM #AllProposalID  ORDER BY [External or Embedded Campaign Id]

------------------------------
-- GET Max Report Data Date
------------------------------
 
SELECT   		
		[Order Id],
		[Campaign Identifier], 
		[Embedded Campaign Id],
		[Report Data Date]	= MAX([Report Data Date])
INTO #MaxReportDataDate
FROM ABCAdjusterDashboard 
WHERE	[Order ID]		=	@NewProposalId AND 
		[Billable Creative] IS NULL  
GROUP BY 

		[Order Id],
		[Campaign Identifier], 
		[Embedded Campaign Id] 
														
-- SELECT * FROM #MaxReportDataDate ORDER BY [External or Embedded Campaign Id]


-------------------------------
-- #AllRowsForOneProposalID
-------------------------------

SELECT  [Order Id], 
		[Campaign Identifier], 
				
		[Contracted Goal],
		[Campaign Start]	AS CampStart, 
		[Campaign End]		AS CampEnd	,
		[Embedded Campaign Id] ,
		[Report Data Date],
		[Local Server Name]
INTO #AllRowsForOneProposalID
FROM ABCAdjusterDashboard 
WHERE	[Order ID]		=	@NewProposalId AND 
		[Billable Creative] IS NULL 



-- SELECT * FROM #AllRowsForOneProposalID ORDER BY [External or Embedded Campaign Id]

--------------------------------------------------------------
-- To Get [Contracted Goal], [Campaign Start], [Campaign End]
--------------------------------------------------------------
SELECT A.* 
INTO #FinalRowsToBeJoined
FROM #AllRowsForOneProposalID A
INNER JOIN #MaxReportDataDate M ON 
			A.[Order ID]						=	M.[Order ID]						AND
			A.[Campaign Identifier]					=	M.[Campaign Identifier]					AND
			A.[Order Id]							=	M.[Order Id]							AND
			A.[Embedded Campaign Id]				=	M.[Embedded Campaign Id]	AND
			A.[Report Data Date]					=	M.[Report Data Date]	
			
							
-- SELECT * FROM #FinalRowsToBeJoined ORDER BY [External or Embedded Campaign Id]

------------------------------------------------------
-- Inner Join #AllProposalID With #FinalRowsToBeJoined
------------------------------------------------------

SELECT 

		
		A.[Campaign Identifier], 
		A.[Order Id], 
		A.[Campaign Name], 
		
		A.[Local Server], 
		M.[Local Server Name], 
		M.[Contracted Goal],
		A.[Embedded Campaign Id],
		M.CampStart, 
		M.CampEnd, 
		A.sumClicks,
		A.sumClicks3rdParty,
		A.sumImpressions, 
		A.sumImpressions3ps
INTO #AllCampaignID
FROM #AllProposalID  A
INNER JOIN #FinalRowsToBeJoined M ON 
							
			A.[Campaign Identifier]					=	M.[Campaign Identifier]					AND
			A.[Order Id]							=	M.[Order Id]							AND
			A.[Embedded Campaign Id]				=	M.[Embedded Campaign Id]
			
-- SELECT * FROM #AllCampaignID ORDER BY [External or Embedded Campaign Id]

---------------------------------------------
-- 2. PACING CALCULATION
---------------------------------------------

----------------------------------------------
-- Date and Days
----------------------------------------------

SELECT
	 [Local Server Name],
	[Campaign Identifier],
	[Campaign Start]					=	[CampStart],
	[Campaign End]						=	[CampEnd],
	Today								=	CONVERT(DATETIME,CONVERT(DATE,GETDATE())),
	IsActiveLineItemID					=	CASE WHEN (
														GETDATE()-1	>= [CampStart]	AND  
														GETDATE()-1	<= [CampEnd]
													  ) THEN 1 
											ELSE 0 
											END	,
	[Contracted Goal]					=	ISNULL([Contracted Goal],0),
	[FirstPartyDeliveredImpressions]	=	sumImpressions,						
	[ThirdPartyDeliveredImpressions]	=	sumImpressions3ps
	
		
INTO #AllPacingRows	
FROM #AllCampaignID
	

-- SELECT * FROM #AllPacingRows
  
--------------------
-- Days Calculation
-------------------
  
SELECT 
	#AllPacingRows.*,
	EndDateMinusStartDateDays			=	DATEDIFF(Day,[Campaign Start],[Campaign End]) + 1,
	GetDateMinusStartDateDays			=	DATEDIFF(Day,[Campaign Start],#MaxReportDataDate.[Report Data Date])+1
INTO #CalculatePacing
FROM #AllPacingRows 
INNER JOIN  #MaxReportDataDate ON 
			#AllPacingRows.[Campaign Identifier] = #MaxReportDataDate.[Campaign Identifier]

-- SELECT * FROM #CalculatePacing


--------------------
-- Pacing Calculation
-------------------

SELECT #AllCampaignID.*,		
		FirstPartyPacing = CASE	WHEN ISNULL(#CalculatePacing.[Contracted Goal],0)		<  100												THEN 0
								WHEN #CalculatePacing.[FirstPartyDeliveredImpressions]	=  0												THEN 0
							    WHEN #CalculatePacing.[Contracted Goal]					<> 0 AND #CalculatePacing.[Campaign End] < Today	THEN 100.0 * [FirstPartyDeliveredImpressions] / (#CalculatePacing.[Contracted Goal])
								WHEN #CalculatePacing.[Contracted Goal]					<> 0 AND IsActiveLineItemID = 0						THEN 100.0 * #CalculatePacing.[FirstPartyDeliveredImpressions] / #CalculatePacing.[Contracted Goal]																																		
								WHEN #CalculatePacing.[Contracted Goal]					<> 0 AND IsActiveLineItemID = 1 AND ((#CalculatePacing.[Contracted Goal]/(#CalculatePacing.EndDateMinusStartDateDays))*(#CalculatePacing.GetDateMinusStartDateDays)) > 0 								
																																			THEN 100.0 * [FirstPartyDeliveredImpressions] / ((#CalculatePacing.[Contracted Goal]/(#CalculatePacing.EndDateMinusStartDateDays))*(#CalculatePacing.GetDateMinusStartDateDays))
							ELSE 0																										
							END	,
		ThirdPartyPacing = CASE	WHEN ISNULL(#CalculatePacing.[Contracted Goal],0)		<  100												THEN 0
								WHEN #CalculatePacing.[ThirdPartyDeliveredImpressions]	=  0												THEN 0
								WHEN #CalculatePacing.[Contracted Goal]					<> 0 AND #CalculatePacing.[Campaign End] < Today	THEN 100.0 * [ThirdPartyDeliveredImpressions] / (#CalculatePacing.[Contracted Goal])
								WHEN #CalculatePacing.[Contracted Goal]					<> 0 AND IsActiveLineItemID = 0						THEN 100.0 * #CalculatePacing.[ThirdPartyDeliveredImpressions] / #CalculatePacing.[Contracted Goal]																																		
								WHEN #CalculatePacing.[Contracted Goal]					<> 0 AND IsActiveLineItemID = 1	AND ((#CalculatePacing.[Contracted Goal]/(EndDateMinusStartDateDays))*(GetDateMinusStartDateDays)) >0 								
																																			THEN 100.0 * [ThirdPartyDeliveredImpressions] / ((#CalculatePacing.[Contracted Goal]/(#CalculatePacing.EndDateMinusStartDateDays))*(#CalculatePacing.GetDateMinusStartDateDays))																															
						   ELSE 0																											
						   END,					
		Variance		 = ISNULL(CASE WHEN [FirstPartyDeliveredImpressions]			<> 0												THEN 100.0 *(#CalculatePacing.[ThirdPartyDeliveredImpressions] - #CalculatePacing.[FirstPartyDeliveredImpressions]) / #CalculatePacing.[FirstPartyDeliveredImpressions]												
						   ELSE 0 
						   END,0)  

INTO #AllColumns
FROM #CalculatePacing  
INNER JOIN	#AllCampaignID ON 
			#CalculatePacing.[Campaign Identifier] = #AllCampaignID.[Campaign Identifier]
ORDER BY 
[Campaign Identifier]
 
 
 
----------------
-- FINAL TABLE
----------------
 
SELECT 
	
	AllColumns.[Campaign Identifier],
	AllColumns.[Order Id]	,
	[Campaign Name]	,
	
	[Local Server]	,
	[Contracted Goal],
	[Local Server Name],
	[Embedded Campaign Id],	
	CampStart,	
	CampEnd,	
	sumImpressions,	
	sumImpressions3ps,	
	sumClicks,
	sumClicks3rdParty,
	CTR					= CASE WHEN sumImpressions		> 0 THEN 1.0 * sumClicks/sumImpressions				ELSE 0 END, 
	CTR3ps				= CASE WHEN sumImpressions3ps	> 0 THEN 1.0 * sumClicks3rdParty/sumImpressions3ps	ELSE 0 END, 
	FirstPartyPacing	= ROUND(FirstPartyPacing,0),	
	ThirdPartyPacing	= ROUND(ThirdPartyPacing,0),	
	Variance			= ROUND(Variance,0),
	VideoAd				=	CASE WHEN LongformOrDisplayAds.[Campaign Identifier] IS NOT NULL THEN 'Y'
							ELSE 'N'
							END
	
	,DC.[O&O Ad Views]
	,DC.[O&O Clicks]
	,DC.[On-Target Events]
	,DemoComp = CASE WHEN DC.[O&O Ad Views] > 0 THEN 1.0 * DC.[On-Target Events] / DC.[O&O Ad Views] ELSE 0 END 

	,CR.[Total Impressions that CAN report Ads Quartiles]
	,count25 = CR.[Ads viewed upto 25% of total ad duration]
	,count50 = CR.[Ads viewed upto 50% of total ad duration]
	,count75 = CR.[Ads viewed upto 75% of total ad duration]
	,count100 = CR.[100% of Ads Viewed]
	,CR.[Percentage of ad views that reached 25% of total ad duration]
	,CR.[Percentage of ad views that reached 50% of total ad duration]
	,CR.[Percentage of ad views that reached 75% of total ad duration]
	,[Percent100] = CR.[Percentage of ad views that reached 100% of total ad duration]
	,CR.[OSI(%)]
	,CR.[FFDR(%)]
	,CR.[On-Target OSI(%)]
	,CR.[On-Target FFDR(%)]
	,CR.[On-Target Calculation Method]
	,CR.[Forced Over Delivery Percent(%)]
	,CR.[Estimated Impression Goal]
	,CR.[Placement Budgeted Impressions]
	
	
	                          
	
FROM #AllColumns AllColumns 

LEFT OUTER JOIN dbo.ABCAdjusterDashboardCompletionRate CR ON AllColumns.[Campaign Identifier] = CR.[MRM Placement ID]

LEFT OUTER JOIN dbo.ABCAdjusterDashboardDemoComp DC ON AllColumns.[Campaign Identifier] = DC.[MRM Placement ID]

LEFT OUTER JOIN (
					
				SELECT DISTINCT ABCAdjusterDashboard.[Order Id], 
						ABCAdjusterDashboard.[Campaign Identifier]
				FROM ABCAdjusterDashboard 
				WHERE 
				[Billable Creative]				IS NOT NULL   AND 
				ABCAdjusterDashboard.[Order Id]	=	@NewProposalId AND 
				[Ad Unit Name] IN 
				(
					'LF MidRoll',
					'LF MidRoll 1',
					'LF MidRoll 1A',
					'LF MidRoll 2',
					'LF MidRoll 2A',
					'LF MidRoll 3',
					'LF MidRoll 3A',
					'LF MidRoll 4',
					'LF MidRoll 4A',
					'LF MidRoll A',
					'LF MidRoll Marketing',
					'LF PreRoll',
					'LF PreRoll A',
					'LF PreRoll B',
					'LF PreRoll Marketing',
					'Live MidRoll',
					'Live PreRoll',
					'SF PostRoll End Card',
					'SF PostRoll Marketing',
					'SF PreRoll',
					'SF Video'
				 )
				) AS LongformOrDisplayAds ON 
				
				AllColumns.[Campaign Identifier]	=	LongformOrDisplayAds.[Campaign Identifier] AND 
				AllColumns.[Order Id]				=	LongformOrDisplayAds.[Order Id]



 

--------------------
-- DROP
--------------------

DROP TABLE #AllCampaignID, #MaxReportDataDate, #AllRowsForOneProposalID, #FinalRowsToBeJoined, #AllProposalID
DROP TABLE #AllPacingRows, #CalculatePacing, #AllColumns



/*

EXECUTE SageBizOps.dbo.[USP_ABC_Get_LineItemPacing_by_OrderID] 4328914

*/
