import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    """
    Starts (creates) the SageMaker endpoint using the existing endpoint configuration.
    """
    endpoint_name = os.environ["ENDPOINT_NAME"]
    endpoint_config_name = os.environ["ENDPOINT_CONFIG_NAME"]
    region = os.environ.get("AWS_REGION", "eu-west-1")

    sagemaker = boto3.client("sagemaker", region_name=region)

    try:
        response = sagemaker.describe_endpoint(EndpointName=endpoint_name)
        status = response["EndpointStatus"]
        logger.info(f"Endpoint {endpoint_name} already exists with status: {status}")
        return {
            "statusCode": 200,
            "body": f"Endpoint {endpoint_name} already exists (status: {status})",
        }

    except sagemaker.exceptions.ClientError as e:
        if "Could not find endpoint" in str(e):
            logger.info(
                f"Creating endpoint {endpoint_name} with config {endpoint_config_name}"
            )
            sagemaker.create_endpoint(
                EndpointName=endpoint_name, EndpointConfigName=endpoint_config_name
            )
            return {
                "statusCode": 200,
                "body": f"Endpoint {endpoint_name} creation initiated",
            }
        raise
    except Exception as e:
        logger.error(f"Error starting endpoint: {str(e)}")
        raise
