import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    """
    Stops (deletes) the SageMaker endpoint to save costs.
    The endpoint configuration is preserved for recreation.
    """
    endpoint_name = os.environ["ENDPOINT_NAME"]
    region = os.environ.get("AWS_REGION", "eu-west-1")

    sagemaker = boto3.client("sagemaker", region_name=region)

    try:
        response = sagemaker.describe_endpoint(EndpointName=endpoint_name)
        status = response["EndpointStatus"]

        if status in ["InService", "Creating", "Updating"]:
            logger.info(f"Deleting endpoint {endpoint_name} (current status: {status})")
            sagemaker.delete_endpoint(EndpointName=endpoint_name)
            return {
                "statusCode": 200,
                "body": f"Endpoint {endpoint_name} deletion initiated",
            }
        else:
            logger.info(
                f"Endpoint {endpoint_name} is in status {status}, skipping deletion"
            )
            return {
                "statusCode": 200,
                "body": f"Endpoint {endpoint_name} is already in status {status}",
            }

    except sagemaker.exceptions.ClientError as e:
        if "Could not find endpoint" in str(e):
            logger.info(f"Endpoint {endpoint_name} does not exist, nothing to delete")
            return {"statusCode": 200, "body": f"Endpoint {endpoint_name} does not exist"}
        raise
    except Exception as e:
        logger.error(f"Error stopping endpoint: {str(e)}")
        raise
